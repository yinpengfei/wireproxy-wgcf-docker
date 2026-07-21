# wireproxy-wgcf

A small Docker setup that exposes Cloudflare WARP as a SOCKS5 proxy through
`wireproxy` and `wgcf`.

It does not need `privileged`, `NET_ADMIN`, or `/dev/net/tun` because wireproxy
runs WireGuard in userspace.

## Components

- `wgcf`: `virb3/wgcf:2.2.31`
- `wireproxy`: built from `github.com/windtf/wireproxy/cmd/wireproxy@v1.1.3`
- builder image: `golang:1.26-alpine`
- runtime image: `alpine:3.22`

The build applies two small, version-pinned patches to make the SOCKS copy
buffer, userspace TCP buffers, connection limit, and idle timeout configurable.
Leaving the new settings empty preserves upstream defaults.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
docker compose logs -f
```

The default compose file uses this Docker Hub image:

```text
pengfeiyin56/wireproxy-wgcf-docker:latest
```

To build locally instead:

```bash
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

The first run accepts Cloudflare WARP terms, registers a device, and creates
these files under `data/`:

- `wgcf-account.toml`
- `wgcf-profile.conf`
- `wireproxy.conf`

Do not commit `data/`. It contains account and private key material.

## Defaults

The example config binds SOCKS5 to localhost on port `1081`:

```text
socks5h://127.0.0.1:1081
```

This avoids conflicts with common local `1080` services.

## Test

```bash
curl --proxy socks5h://127.0.0.1:1081 \
  https://www.cloudflare.com/cdn-cgi/trace
```

The output should include:

```text
warp=on
```

For a small timing check:

```bash
curl --proxy socks5h://127.0.0.1:1081 \
  -o /dev/null \
  -w 'connect=%{time_connect} total=%{time_total} speed=%{speed_download} bytes/s\n' \
  'https://speed.cloudflare.com/__down?bytes=20000000'
```

## Endpoint Tuning

If the container is healthy but requests through SOCKS5 time out, WARP may not
be completing its WireGuard handshake with the generated endpoint.

Set this in `.env` and restart:

```dotenv
WG_ENDPOINT=162.159.192.1:2408
```

This endpoint was tested successfully on the HK server where the default
`engage.cloudflareclient.com:2408` endpoint timed out.

## Resource Profiles

The default profile preserves upstream wireproxy and Go runtime behavior:

```dotenv
MEMORY_PROFILE=default
```

For a small server, enable:

```dotenv
MEMORY_PROFILE=low
```

Or use the included Compose override without editing `.env`:

```bash
docker compose -f compose.yaml -f compose.low-memory.yaml up -d
```

The built-in profiles are:

| Setting | `default` | `low` | `balanced` |
| --- | ---: | ---: | ---: |
| SOCKS buffer, each direction | 256 KiB | 64 KiB | 128 KiB |
| TCP receive/send default | 1 MiB | 512 KiB | 1 MiB |
| TCP receive/send maximum | 4 MiB | 2 MiB | 4 MiB |
| `GOMEMLIMIT` | unset | 96 MiB | 160 MiB |
| Maximum SOCKS connections | unlimited | 64 | 256 |
| Idle timeout | unset | 10 minutes | 15 minutes |

All values can be overridden individually in `.env`. Buffer sizes are bytes:

```dotenv
SOCKS_BUFFER_SIZE=65536
TCP_RECV_BUFFER_MIN=4096
TCP_RECV_BUFFER_DEFAULT=524288
TCP_RECV_BUFFER_MAX=2097152
TCP_SEND_BUFFER_MIN=4096
TCP_SEND_BUFFER_DEFAULT=524288
TCP_SEND_BUFFER_MAX=2097152
GOMEMLIMIT=96MiB
GOGC=75
MAX_CONNECTIONS=64
IDLE_TIMEOUT=10m
```

In a four-connection, 80 MB download test on the HK server, the `low` profile
settled at about 57 MiB versus about 107 MiB for `default`, without a measurable
throughput loss. This is one test, not a universal benchmark.

## DNS and Health

For `socks5h` requests, leave `WG_DNS` empty to retain the DNS servers generated
by wgcf, or override them explicitly:

```dotenv
WG_DNS=1.1.1.1,1.0.0.1
RESOLVE_STRATEGY=auto
```

To reduce repeated `socks5h` lookups, enable the bounded in-process DNS cache:

```dotenv
DNS_CACHE_TTL=60s
DNS_CACHE_NEGATIVE_TTL=10s
DNS_CACHE_MAX_ENTRIES=1024
```

The cache uses a fixed TTL because wireproxy's resolver does not expose DNS
record TTLs. It keeps at most the configured number of hostname entries and
coalesces concurrent requests for one hostname into one upstream query. Leave
`DNS_CACHE_TTL` empty to disable it.

The container health check uses wireproxy's `/readyz` endpoint and sends an ICMP
probe through WARP. It is enabled by default:

```dotenv
CHECK_ALIVE=1.1.1.1
CHECK_ALIVE_INTERVAL=15
```

Set `CHECK_ALIVE=` to disable the tunnel probe. Docker reports an unhealthy
container but does not restart it solely because of health status; the
`restart: unless-stopped` policy still handles process or container exits.

## Logs and Recovery

The Compose service rotates Docker JSON logs by size, not by calendar date:
5 MiB per file, at most 7 files, and compressed rotated files. This caps the
uncompressed retention at roughly 35 MiB. Change the `logging` section in
`compose.yaml` if you need a different capacity. The settings take effect when
the container is recreated with `docker compose up -d`.

Use `LOG_LEVEL=error` to retain `ERROR` messages while suppressing routine
request logs and WireGuard DEBUG logs. Use `LOG_LEVEL=debug` for temporary
diagnosis; it can generate a large number of DNS, health-check, and keepalive
lines.

The `watchdog/` directory contains an optional host-side systemd timer. It
checks Docker's health status every 30 seconds and restarts the container only
after the WARP probe is `unhealthy`. It has a 90-second restart cooldown and a
three-restarts-per-hour circuit breaker. It is intentionally not a container:
mounting `/var/run/docker.sock` into a helper container would grant it broad
control of the Docker host.

Install it on an Ubuntu host after reviewing the paths:

```bash
sudo install -m 0755 watchdog/wireproxy-watchdog.sh /usr/local/sbin/wireproxy-watchdog
sudo install -m 0644 watchdog/wireproxy-watchdog.service /etc/systemd/system/
sudo install -m 0644 watchdog/wireproxy-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wireproxy-watchdog.timer
```

Check it with:

```bash
systemctl list-timers wireproxy-watchdog.timer
journalctl -u wireproxy-watchdog.service
```

## LAN Access

To expose the proxy beyond localhost, use:

```dotenv
BIND_ADDRESS=0.0.0.0
SOCKS_USERNAME=your_user
SOCKS_PASSWORD=your_strong_password
```

Also restrict access with the host firewall. Do not expose an unauthenticated
SOCKS5 proxy to the public internet.

## Notes

- WARP does not let you choose the exit country.
- wireproxy SOCKS5 does not support UDP Associate.
- HTTP/2 connection reuse is handled by the client. wireproxy shares one WARP
  peer across all SOCKS connections but does not pool unrelated target TCP
  connections.
- Smaller buffers reduce memory and read-ahead traffic but may reduce throughput
  on high-latency paths. Start with a profile before using fine-grained values.

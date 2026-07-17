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
- This setup optimizes for low memory and simple deployment, not maximum raw
  throughput.

#!/bin/sh
set -eu

PROFILE=/data/wgcf-profile.conf
ACCOUNT=/data/wgcf-account.toml
CONFIG=/data/wireproxy.conf

set_interface_value() {
    key="$1"
    value="$2"
    if grep -q "^${key}[[:space:]]*=" "$PROFILE"; then
        sed -i "s#^${key}[[:space:]]*=.*#${key} = ${value}#" "$PROFILE"
    else
        sed -i "/^\[Interface\]$/a ${key} = ${value}" "$PROFILE"
    fi
}

remove_interface_value() {
    sed -i "/^$1[[:space:]]*=/d" "$PROFILE"
}

validate_positive_integer() {
    name="$1"
    value="$2"
    case "$value" in
        *[!0-9]*|'') echo "$name must be a positive integer" >&2; exit 1 ;;
    esac
    if [ "$value" -le 0 ]; then
        echo "$name must be greater than zero" >&2
        exit 1
    fi
}

if [ ! -s "$ACCOUNT" ]; then
    echo "First run: registering a WARP device..."
    wgcf register --accept-tos
fi

if [ ! -s "$PROFILE" ]; then
    echo "Generating WireGuard profile..."
    wgcf generate
fi

MTU_VALUE="${WG_MTU:-1280}"
case "$MTU_VALUE" in
    *[!0-9]*|'') echo "WG_MTU must be an integer" >&2; exit 1 ;;
esac

set_interface_value MTU "$MTU_VALUE"

if [ -n "${WG_ENDPOINT:-}" ]; then
    case "$WG_ENDPOINT" in
        *[!A-Za-z0-9.:-]*|'') echo "WG_ENDPOINT contains unsupported characters" >&2; exit 1 ;;
    esac
    if grep -q '^Endpoint[[:space:]]*=' "$PROFILE"; then
        sed -i "s#^Endpoint[[:space:]]*=.*#Endpoint = $WG_ENDPOINT#" "$PROFILE"
    else
        sed -i "/^\[Peer\]$/a Endpoint = $WG_ENDPOINT" "$PROFILE"
    fi
fi

case "${MEMORY_PROFILE:-default}" in
    ''|default) ;;
    low)
        : "${SOCKS_BUFFER_SIZE:=65536}"
        : "${TCP_RECV_BUFFER_MIN:=4096}"
        : "${TCP_RECV_BUFFER_DEFAULT:=524288}"
        : "${TCP_RECV_BUFFER_MAX:=2097152}"
        : "${TCP_SEND_BUFFER_MIN:=4096}"
        : "${TCP_SEND_BUFFER_DEFAULT:=524288}"
        : "${TCP_SEND_BUFFER_MAX:=2097152}"
        : "${GOMEMLIMIT:=96MiB}"
        : "${GOGC:=75}"
        : "${MAX_CONNECTIONS:=64}"
        : "${IDLE_TIMEOUT:=10m}"
        ;;
    balanced)
        : "${SOCKS_BUFFER_SIZE:=131072}"
        : "${TCP_RECV_BUFFER_MIN:=4096}"
        : "${TCP_RECV_BUFFER_DEFAULT:=1048576}"
        : "${TCP_RECV_BUFFER_MAX:=4194304}"
        : "${TCP_SEND_BUFFER_MIN:=4096}"
        : "${TCP_SEND_BUFFER_DEFAULT:=1048576}"
        : "${TCP_SEND_BUFFER_MAX:=4194304}"
        : "${GOMEMLIMIT:=160MiB}"
        : "${GOGC:=100}"
        : "${MAX_CONNECTIONS:=256}"
        : "${IDLE_TIMEOUT:=15m}"
        ;;
    *) echo "MEMORY_PROFILE must be default, low, or balanced" >&2; exit 1 ;;
esac

for item in \
    "TCPReceiveBufferMin:${TCP_RECV_BUFFER_MIN:-}" \
    "TCPReceiveBufferDefault:${TCP_RECV_BUFFER_DEFAULT:-}" \
    "TCPReceiveBufferMax:${TCP_RECV_BUFFER_MAX:-}" \
    "TCPSendBufferMin:${TCP_SEND_BUFFER_MIN:-}" \
    "TCPSendBufferDefault:${TCP_SEND_BUFFER_DEFAULT:-}" \
    "TCPSendBufferMax:${TCP_SEND_BUFFER_MAX:-}"
do
    key="${item%%:*}"
    value="${item#*:}"
    if [ -n "$value" ]; then
        validate_positive_integer "$key" "$value"
        set_interface_value "$key" "$value"
    else
        remove_interface_value "$key"
    fi
done

if [ -n "${WG_DNS:-}" ]; then
    case "$WG_DNS" in
        *[!0-9A-Fa-f:.,[:space:]]*) echo "WG_DNS contains unsupported characters" >&2; exit 1 ;;
    esac
    set_interface_value DNS "$WG_DNS"
fi

if [ -n "${CHECK_ALIVE:-}" ]; then
    case "$CHECK_ALIVE" in
        *[!0-9A-Fa-f:.,[:space:]]*) echo "CHECK_ALIVE contains unsupported characters" >&2; exit 1 ;;
    esac
    validate_positive_integer CHECK_ALIVE_INTERVAL "${CHECK_ALIVE_INTERVAL:-15}"
    set_interface_value CheckAlive "$CHECK_ALIVE"
    set_interface_value CheckAliveInterval "${CHECK_ALIVE_INTERVAL:-15}"
else
    remove_interface_value CheckAlive
    remove_interface_value CheckAliveInterval
fi

if [ -n "${GOMEMLIMIT:-}" ]; then
    export GOMEMLIMIT
else
    unset GOMEMLIMIT
fi
if [ -n "${GOGC:-}" ]; then
    validate_positive_integer GOGC "$GOGC"
    export GOGC
else
    unset GOGC
fi

case "${SOCKS_USERNAME:-}${SOCKS_PASSWORD:-}" in
    *"
"*) echo "SOCKS_USERNAME and SOCKS_PASSWORD must not contain newlines" >&2; exit 1 ;;
esac

{
    echo "WGConfig = $PROFILE"
    echo
    echo "[Socks5]"
    echo "BindAddress = 0.0.0.0:1080"
    if [ -n "${SOCKS_USERNAME:-}" ] || [ -n "${SOCKS_PASSWORD:-}" ]; then
        if [ -z "${SOCKS_USERNAME:-}" ] || [ -z "${SOCKS_PASSWORD:-}" ]; then
            echo "SOCKS_USERNAME and SOCKS_PASSWORD must be set together" >&2
            exit 1
        fi
        echo "Username = $SOCKS_USERNAME"
        echo "Password = $SOCKS_PASSWORD"
    fi
    if [ -n "${SOCKS_BUFFER_SIZE:-}" ]; then
        validate_positive_integer SOCKS_BUFFER_SIZE "$SOCKS_BUFFER_SIZE"
        echo "BufferSize = $SOCKS_BUFFER_SIZE"
    fi
    if [ -n "${MAX_CONNECTIONS:-}" ]; then
        validate_positive_integer MAX_CONNECTIONS "$MAX_CONNECTIONS"
        echo "MaxConnections = $MAX_CONNECTIONS"
    fi
    if [ -n "${IDLE_TIMEOUT:-}" ]; then
        case "$IDLE_TIMEOUT" in
            *[!0-9a-zA-Z.µ]*) echo "IDLE_TIMEOUT contains unsupported characters" >&2; exit 1 ;;
        esac
        echo "IdleTimeout = $IDLE_TIMEOUT"
    fi
    echo
    echo "[Resolve]"
    case "${RESOLVE_STRATEGY:-auto}" in
        auto|ipv4|ipv6) echo "ResolveStrategy = ${RESOLVE_STRATEGY:-auto}" ;;
        *) echo "RESOLVE_STRATEGY must be auto, ipv4, or ipv6" >&2; exit 1 ;;
    esac
} > "$CONFIG"

chmod 600 "$ACCOUNT" "$PROFILE" "$CONFIG"

echo "Starting wireproxy on container port 1080, MTU=$MTU_VALUE, memory-profile=${MEMORY_PROFILE:-default}"
exec wireproxy -c "$CONFIG" -i 127.0.0.1:9080

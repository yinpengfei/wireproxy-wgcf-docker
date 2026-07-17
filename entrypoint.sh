#!/bin/sh
set -eu

PROFILE=/data/wgcf-profile.conf
ACCOUNT=/data/wgcf-account.toml
CONFIG=/data/wireproxy.conf

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

if grep -q '^MTU[[:space:]]*=' "$PROFILE"; then
    sed -i "s/^MTU[[:space:]]*=.*/MTU = $MTU_VALUE/" "$PROFILE"
else
    sed -i "/^\[Interface\]$/a MTU = $MTU_VALUE" "$PROFILE"
fi

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
} > "$CONFIG"

chmod 600 "$ACCOUNT" "$PROFILE" "$CONFIG"

echo "Starting wireproxy on container port 1080, MTU=$MTU_VALUE"
exec wireproxy -c "$CONFIG"

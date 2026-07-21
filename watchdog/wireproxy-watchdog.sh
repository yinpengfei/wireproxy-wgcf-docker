#!/bin/sh
# Run from a root-owned systemd service on the Docker host, not in the proxy
# container. It restarts only after Docker reports the real WARP probe unhealthy.
set -eu

CONTAINER="${CONTAINER:-wireproxy-wgcf}"
STATE_DIR="${STATE_DIR:-/var/lib/wireproxy-watchdog}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-90}"
MAX_RESTARTS_PER_HOUR="${MAX_RESTARTS_PER_HOUR:-3}"

mkdir -p "$STATE_DIR"
now="$(date +%s)"
status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || true)"

[ "$status" = "unhealthy" ] || exit 0

last_file="$STATE_DIR/last-restart"
history_file="$STATE_DIR/restarts"
last=0
[ -r "$last_file" ] && last="$(cat "$last_file")"
case "$last" in *[!0-9]*|'') last=0 ;; esac

# Let a just-started tunnel finish its handshake before deciding it failed again.
[ $((now - last)) -ge "$COOLDOWN_SECONDS" ] || exit 0

cutoff=$((now - 3600))
touch "$history_file"
awk -v cutoff="$cutoff" '$1 >= cutoff { print $1 }' "$history_file" > "$history_file.tmp"
mv "$history_file.tmp" "$history_file"
count="$(wc -l < "$history_file")"
[ "$count" -lt "$MAX_RESTARTS_PER_HOUR" ] || exit 0

echo "$(date -Is) restarting $CONTAINER after unhealthy WARP probe" >&2
docker restart "$CONTAINER" >/dev/null
printf '%s\n' "$now" > "$last_file"
printf '%s\n' "$now" >> "$history_file"

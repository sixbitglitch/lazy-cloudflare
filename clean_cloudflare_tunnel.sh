#!/usr/bin/env bash
# Clean all Cloudflare tunnels and processes on the host.
# - Kills any running cloudflared processes
# - Stops and disables all cloudflared systemd services (cloudflared.service, cloudflared-*.service)
# - Deletes all tunnels for the current (or specified) user
# - Removes tunnel config and credential files from ~/.cloudflared
# Usage: ./clean_cloudflare_tunnel.sh [USER]
#   USER  optional; run tunnel delete as this user (default: current user). Use when cleaning after setup run with sudo.

set -e

REAL_USER="${1:-${SUDO_USER:-$USER}}"
CLOUDFLARED_DIR="$HOME/.cloudflared"
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "$USER" ]; then
  CLOUDFLARED_DIR="$(eval echo "~$REAL_USER")/.cloudflared"
fi

echo "== Cleaning all Cloudflare tunnels and processes =="

# 1) Stop and disable all cloudflared systemd services, then remove unit files
echo "Stopping systemd services..."
if command -v systemctl &>/dev/null; then
  sudo systemctl list-unit-files --no-legend 'cloudflared*' 2>/dev/null | awk '{print $1}' | while read -r s; do
    sudo systemctl stop "$s" 2>/dev/null || true
    sudo systemctl disable "$s" 2>/dev/null || true
    echo "  stopped/disabled $s"
  done
  for dir in /etc/systemd/system /usr/lib/systemd/system; do
    [ -d "$dir" ] || continue
    for f in "$dir"/cloudflared.service "$dir"/cloudflared-*.service; do
      [ -f "$f" ] || continue
      sudo rm -f "$f"
      echo "  removed $f"
    done
  done
  sudo systemctl daemon-reload 2>/dev/null || true
fi

# 2) Kill any remaining cloudflared processes
echo "Killing cloudflared processes..."
if pkill -x cloudflared 2>/dev/null; then
  echo "  killed cloudflared process(es)"
else
  killall cloudflared 2>/dev/null || true
fi
sleep 1
# Force kill if still around
pkill -9 -x cloudflared 2>/dev/null || true
killall -9 cloudflared 2>/dev/null || true
echo "  done"

# 3) Delete all tunnels (must run as user that owns cert.pem)
if command -v cloudflared &>/dev/null && [ -d "$CLOUDFLARED_DIR" ]; then
  echo "Deleting tunnels..."
  TUNNEL_LIST=""
  if [ "$(id -u)" -eq 0 ] && [ -n "$REAL_USER" ]; then
    TUNNEL_LIST=$(sudo -u "$REAL_USER" cloudflared tunnel list 2>/dev/null) || true
  else
    TUNNEL_LIST=$(cloudflared tunnel list 2>/dev/null) || true
  fi
  if [ -n "$TUNNEL_LIST" ]; then
    echo "$TUNNEL_LIST" | tail -n +2 | while read -r line; do
      # Format: UUID NAME CREATED
      name=$(echo "$line" | awk '{print $2}')
      [ -z "$name" ] && continue
      if [ "$(id -u)" -eq 0 ] && [ -n "$REAL_USER" ]; then
        sudo -u "$REAL_USER" cloudflared tunnel delete -f "$name" 2>/dev/null && echo "  deleted tunnel: $name" || true
      else
        cloudflared tunnel delete -f "$name" 2>/dev/null && echo "  deleted tunnel: $name" || true
      fi
    done
  fi
fi

# 4) Remove tunnel config and credential files (keep cert.pem so login persists)
echo "Removing tunnel config and credentials from $CLOUDFLARED_DIR..."
if [ -d "$CLOUDFLARED_DIR" ]; then
  for f in "$CLOUDFLARED_DIR"/config-*.yml "$CLOUDFLARED_DIR"/*.json; do
    [ -e "$f" ] || continue
    rm -f "$f" 2>/dev/null || sudo rm -f "$f" 2>/dev/null || true
    echo "  removed $(basename "$f")"
  done
fi

echo ""
echo "Clean complete. cert.pem was kept; run setup again or 'cloudflared tunnel login' if you need to re-auth."

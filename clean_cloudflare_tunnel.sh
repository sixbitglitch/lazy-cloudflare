#!/usr/bin/env bash
# Clean only THIS HOST: stop services, kill processes, remove local config/credentials. Does NOT delete any tunnels from your Cloudflare account.
# - Kills any running cloudflared processes
# - Stops and disables all cloudflared systemd services on this machine
# - Removes tunnel config and credential files from ~/.cloudflared (keeps cert.pem)
# To delete tunnels from the account, use remove_cloudflare_tunnel.sh config.yml (only removes tunnels listed in that config).
# Usage: ./clean_cloudflare_tunnel.sh [USER]
#   USER  optional; use this user's ~/.cloudflared when run as root (e.g. sudo ./clean_cloudflare_tunnel.sh deploy).

set -e

REAL_USER="${1:-${SUDO_USER:-$USER}}"
CLOUDFLARED_DIR="$HOME/.cloudflared"
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "$USER" ]; then
  CLOUDFLARED_DIR="$(eval echo "~$REAL_USER")/.cloudflared"
fi

echo "== Cleaning this host only (services, processes, local config). Not touching account tunnels. =="

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

# 3) Remove tunnel config and credential files (keep cert.pem so login persists). Does NOT delete tunnels from Cloudflare account.
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

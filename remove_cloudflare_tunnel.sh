#!/usr/bin/env bash
# Remove all Cloudflare tunnels defined in config: stop and disable services, delete tunnels, remove config and credentials.
# Usage: ./remove_cloudflare_tunnel.sh config.yml

set -e
CONFIG_FILE="${1:?Usage: $0 config.yml}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE"
  exit 1
fi

CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"

parse_tunnels() {
  if command -v ruby &>/dev/null; then
    ruby -r yaml -e "
      h = YAML.load_file(ARGV[0])
      (h && h['tunnels']).to_a.each { |t| puts [t['name'], t['hostname'], t['service']].join('|') }
    " "$CONFIG_FILE" 2>/dev/null
  elif command -v python3 &>/dev/null; then
    python3 -c "
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
for t in (d or {}).get('tunnels') or []:
    print(t.get('name','') + '|' + t.get('hostname','') + '|' + t.get('service',''))
" "$CONFIG_FILE" 2>/dev/null
  else
    echo "Need ruby or python3 (with PyYAML) to parse config." >&2
    exit 1
  fi
}

TUNNELS_LINES="$(parse_tunnels)"
if [ -z "$TUNNELS_LINES" ]; then
  echo "No tunnels found in $CONFIG_FILE" >&2
  exit 1
fi

CLOUDFLARED_DIR="${CLOUDFLARED_DIR:-$HOME/.cloudflared}"
REAL_USER="${SUDO_USER:-$USER}"
if [ -n "$SUDO_USER" ]; then
  REAL_USER_HOME="$(eval echo "~$SUDO_USER")"
  CLOUDFLARED_DIR="$REAL_USER_HOME/.cloudflared"
else
  REAL_USER_HOME="$HOME"
fi

SYSTEMD_DIR="/etc/systemd/system"

echo "Removing Cloudflare tunnels from config..."
while IFS='|' read -r name hostname service; do
  [ -z "$name" ] && continue
  SVC="cloudflared-${name}.service"
  UNIT_FILE="$SYSTEMD_DIR/$SVC"

  echo "--- $name ---"
  sudo systemctl stop "$SVC" 2>/dev/null || true
  sudo systemctl disable "$SVC" 2>/dev/null || true
  if [ -f "$UNIT_FILE" ]; then
    sudo rm -f "$UNIT_FILE"
    echo "  Removed $UNIT_FILE"
  fi

  TUNNEL_ID=""
  if command -v cloudflared &>/dev/null; then
    if [ "$(id -u)" -eq 0 ] && [ -n "$REAL_USER" ]; then
      TUNNEL_ID=$(sudo -u "$REAL_USER" cloudflared tunnel list 2>/dev/null | awk -v n="$name" '$2==n {print $1; exit}')
    else
      TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$name" '$2==n {print $1; exit}')
    fi
  fi
  if [ -n "$TUNNEL_ID" ]; then
    if [ "$(id -u)" -eq 0 ] && [ -n "$REAL_USER" ]; then
      sudo -u "$REAL_USER" cloudflared tunnel delete -f "$name" 2>/dev/null && echo "  Deleted tunnel $name ($TUNNEL_ID)" || echo "  Could not delete tunnel $name (run as $REAL_USER: cloudflared tunnel delete $name)"
    else
      cloudflared tunnel delete -f "$name" 2>/dev/null && echo "  Deleted tunnel $name ($TUNNEL_ID)" || echo "  Could not delete tunnel $name (run: cloudflared tunnel delete $name)"
    fi
  fi

  TUNNEL_CONFIG="$CLOUDFLARED_DIR/config-${name}.yml"
  if [ -f "$TUNNEL_CONFIG" ]; then
    rm -f "$TUNNEL_CONFIG"
    echo "  Removed $TUNNEL_CONFIG"
  fi

  if [ -n "$TUNNEL_ID" ] && [ -f "$CLOUDFLARED_DIR/${TUNNEL_ID}.json" ]; then
    rm -f "$CLOUDFLARED_DIR/${TUNNEL_ID}.json"
    echo "  Removed credentials ${TUNNEL_ID}.json"
  fi
  echo ""
done <<< "$TUNNELS_LINES"

sudo systemctl daemon-reload 2>/dev/null || true
echo "Done. DNS CNAMEs (e.g. hostname -> <uuid>.cfargotunnel.com) are left in Cloudflare; remove them in the dashboard if desired."

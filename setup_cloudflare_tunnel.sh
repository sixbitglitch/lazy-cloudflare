#!/usr/bin/env bash
# Cloudflare Tunnel setup — config-driven, one tunnel at a time.
# Usage: ./setup_cloudflare_tunnel.sh config.yml
#
# 1) Installs cloudflared on the host if missing
# 2) Logs in via cloudflared tunnel login (open URL in browser)
# 3) Creates each tunnel from config (name, hostname, service), routes DNS, writes per-tunnel config
# 4) Installs and enables systemd services so tunnels auto-start (one service per tunnel: cloudflared-<name>.service)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:?Usage: $0 config.yml}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found: $CONFIG_FILE"
  exit 1
fi

# Resolve path so it's valid when we cd later
CONFIG_FILE="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"

# Parse YAML config: output one line per tunnel: name|hostname|service
# Requires ruby (stdlib yaml) or python3 with PyYAML.
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
    echo "Need ruby or python3 (with PyYAML) to parse config. Install: gem install not needed (ruby has yaml), or pip install pyyaml" >&2
    exit 1
  fi
}

TUNNELS_LINES="$(parse_tunnels)"
if [ -z "$TUNNELS_LINES" ]; then
  echo "No tunnels found in $CONFIG_FILE (expected key: tunnels: list of name/hostname/service)" >&2
  exit 1
fi

CLOUDFLARED_DIR="${CLOUDFLARED_DIR:-$HOME/.cloudflared}"
REAL_USER="${SUDO_USER:-$USER}"
if [ -n "$SUDO_USER" ]; then
  REAL_USER_HOME="$(eval echo "~$SUDO_USER")"
else
  REAL_USER_HOME="$HOME"
fi

# When running under sudo, use the invoking user's .cloudflared
if [ -n "$SUDO_USER" ] && [ "$REAL_USER_HOME" != "$HOME" ]; then
  CLOUDFLARED_DIR="$REAL_USER_HOME/.cloudflared"
fi

echo "== Cloudflare Tunnel setup (config: $CONFIG_FILE) =="
echo "Tunnel data dir: $CLOUDFLARED_DIR"
echo ""

# 1) Install cloudflared if missing
if ! command -v cloudflared &>/dev/null; then
  echo ">>> Step 1: Installing cloudflared..."
  OS=$(uname -s)
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64";;
    aarch64) ARCH="arm64";;
    *)       ARCH="amd64";;
  esac
  case "$OS" in
    Linux)   CLOUDFLARED_RELEASE="cloudflared-linux-${ARCH}";;
    Darwin)  CLOUDFLARED_RELEASE="cloudflared-darwin-${ARCH}";;
    *)       echo "Unsupported OS: $OS"; exit 1;;
  esac
  CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
  if [ -w "$(dirname "$CLOUDFLARED_BIN")" ] 2>/dev/null; then
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CLOUDFLARED_RELEASE}" -o "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
  else
    sudo curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/${CLOUDFLARED_RELEASE}" -o "$CLOUDFLARED_BIN"
    sudo chmod +x "$CLOUDFLARED_BIN"
  fi
  echo "Installed cloudflared at $(command -v cloudflared)."
else
  echo ">>> Step 1: cloudflared already installed."
fi

# 2) Login via CLI (one-time; creates cert.pem)
mkdir -p "$CLOUDFLARED_DIR"
if [ ! -f "$CLOUDFLARED_DIR/cert.pem" ]; then
  echo ""
  echo ">>> Step 2: Log in to Cloudflare (open the URL below in your browser)"
  echo "Select the account that owns the zones for your hostnames."
  echo ""
  cloudflared tunnel login
  echo "Login done."
else
  echo ">>> Step 2: Already logged in (cert.pem exists)."
fi

# 3) Create each tunnel one by one
echo ""
echo ">>> Step 3: Creating tunnels from config..."

while IFS='|' read -r name hostname service; do
  [ -z "$name" ] && continue
  echo "--- Tunnel: $name ($hostname -> $service) ---"

  if ! cloudflared tunnel list 2>/dev/null | grep -q "$name"; then
    cloudflared tunnel create "$name"
  else
    echo "Tunnel '$name' already exists."
  fi

  TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | awk -v n="$name" '$2==n {print $1; exit}')
  if [ -z "$TUNNEL_ID" ]; then
    echo "Could not get tunnel ID for '$name'. Run: cloudflared tunnel list"
    exit 1
  fi

  CREDENTIALS_FILE="$CLOUDFLARED_DIR/${TUNNEL_ID}.json"
  if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "Credentials file not found: $CREDENTIALS_FILE"
    exit 1
  fi

  # Per-tunnel config for running this tunnel only
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/config-${name}.yml"
  {
    echo "tunnel: $TUNNEL_ID"
    echo "credentials-file: $CREDENTIALS_FILE"
    echo ""
    echo "ingress:"
    echo "  - hostname: $hostname"
    echo "    service: $service"
    echo "  - service: http_status:404"
  } > "$TUNNEL_CONFIG"
  echo "Wrote $TUNNEL_CONFIG"

  # Route DNS
  if cloudflared tunnel route dns "$name" "$hostname" --overwrite-dns 2>/dev/null; then
    echo "DNS routed: $hostname -> $name"
  else
    echo "DNS route failed for $hostname (zone may need to be in the same account). You can add CNAME manually: $hostname -> ${TUNNEL_ID}.cfargotunnel.com"
  fi
  echo ""
done <<< "$TUNNELS_LINES"

# 4) Install systemd services (one per tunnel) so they auto-start
echo ">>> Step 4: Installing systemd services (auto-start)..."

CLOUDFLARED_BIN="$(command -v cloudflared)"
SYSTEMD_DIR="/etc/systemd/system"

for line in $TUNNELS_LINES; do
  IFS='|' read -r name hostname service <<< "$line"
  [ -z "$name" ] && continue

  SVC="cloudflared-${name}.service"
  TUNNEL_CONFIG="$CLOUDFLARED_DIR/config-${name}.yml"

  # Service runs as the user that owns the credentials (so it can read ~/.cloudflared)
  UNIT_FILE="$SYSTEMD_DIR/$SVC"
  sudo tee "$UNIT_FILE" >/dev/null << EOF
[Unit]
Description=Cloudflare Tunnel ($name)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$REAL_USER
ExecStart=$CLOUDFLARED_BIN tunnel --config $TUNNEL_CONFIG run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  echo "  Installed $SVC"
  sudo systemctl daemon-reload
  sudo systemctl enable "$SVC"
  sudo systemctl start "$SVC"
done

echo ""
echo "== Setup complete. Tunnels running:"
while IFS='|' read -r name hostname service; do
  [ -z "$name" ] && continue
  echo "  https://$hostname  (service: cloudflared-$name.service)"
done <<< "$TUNNELS_LINES"
echo "Check: sudo systemctl status cloudflared-<name>"

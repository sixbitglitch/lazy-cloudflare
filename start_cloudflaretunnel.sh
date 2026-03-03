#!/usr/bin/env bash
# Start all Cloudflare tunnel services defined in config.
# Usage: ./start_cloudflaretunnel.sh config.yml

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

echo "Starting Cloudflare tunnel services..."
while IFS='|' read -r name hostname service; do
  [ -z "$name" ] && continue
  SVC="cloudflared-${name}.service"
  if sudo systemctl start "$SVC" 2>/dev/null; then
    echo "  Started $SVC"
  else
    echo "  Failed to start $SVC (install with setup_cloudflare_tunnel.sh first)" >&2
    exit 1
  fi
done <<< "$TUNNELS_LINES"
echo "Done."

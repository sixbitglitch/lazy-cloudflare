# Cloudflare Tunnels — Server Setup Tools

A set of tools for setting up and managing **Cloudflare Tunnels** on a server using the **`cloudflared`** CLI. Use these scripts to create tunnels, install the connector, and run tunnels as a service so internal services are exposed securely through Cloudflare without opening firewall ports.

## Prerequisites

- A [Cloudflare](https://cloudflare.com) account.
- **cloudflared** installed on the server. Install from [Cloudflare’s docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/) or:

  ```bash
  # Linux (deb)
  curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared.deb

  # macOS
  brew install cloudflared
  ```

- Your Cloudflare account **Account ID** and (for API use) an **API Token** with permissions for Zone and Tunnel management.

## Quick start (CLI)

1. **Log in** (one-time, creates `~/.cloudflared/cert.pem`):

   ```bash
   cloudflared tunnel login
   ```

   Open the URL it prints and authorize the account.

2. **Create a named tunnel**:

   ```bash
   cloudflared tunnel create <TUNNEL_NAME>
   ```

   Example: `cloudflared tunnel create my-server` → creates tunnel and UUID.

3. **Create a config file** (e.g. `~/.cloudflared/config.yml`):

   ```yaml
   tunnel: <TUNNEL_UUID>
   credentials-file: /path/to/.cloudflared/<TUNNEL_UUID>.json

   ingress:
     - hostname: app.example.com
       service: http://localhost:3000
     - hostname: api.example.com
       service: http://localhost:8080
     - service: http_status:404
   ```

4. **Route a hostname** to the tunnel (one per hostname):

   ```bash
   cloudflared tunnel route dns <TUNNEL_NAME> <hostname>
   ```

   Example: `cloudflared tunnel route dns my-server app.example.com`

5. **Run the tunnel**:

   ```bash
   cloudflared tunnel run <TUNNEL_NAME>
   ```

   For production, install and run as a service (see below).

## What these tools do

The scripts in this repo automate the above using the CLI:

| Goal | CLI / approach |
|------|----------------|
| **Create tunnel** | `cloudflared tunnel create <name>` |
| **List tunnels** | `cloudflared tunnel list` |
| **Route DNS** | `cloudflared tunnel route dns <tunnel> <hostname>` |
| **Run tunnel** | `cloudflared tunnel run <name>` |
| **Install as service** | `cloudflared service install` (after config is in place) |

Config is driven by a YAML file (e.g. `config.yml`) that defines `tunnel`, `credentials-file`, and `ingress` rules.

## Directory layout

```
cloudflare-tools/
├── README.md           # This file
├── config.example.yml  # Example tunnel ingress config
└── scripts/            # (Optional) helpers for create, route, install
```

- **config.example.yml** — Copy to `~/.cloudflared/config.yml` (or `/etc/cloudflared/config.yml` for system-wide) and set your tunnel ID and ingress.
- **scripts/** — Wrappers around `cloudflared` for creating tunnels, routing DNS, and installing the service.

## Installing the tunnel as a service (Linux)

After `config.yml` and credentials are in place (e.g. under `~/.cloudflared/` or `/etc/cloudflared/`):

```bash
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

The tools here are intended to prepare the tunnel and config so that this step works without manual editing.

## References

- [Cloudflare Tunnels (Connect)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Install cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/)
- [Configure a tunnel (config.yml)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/local/)
- [Route DNS](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/local/#route-cloudflare-tunnel-traffic-to-a-dns-record)

# Cloudflare Tunnels — Server Setup Tools

These are a bit janky, I forget commandline stuff alot, and sick of breaking stuff all the time!

A set of tools for setting up and managing **Cloudflare Tunnels** on a server using the **`cloudflared`** CLI. All scripts are **config-driven**: you maintain a single `config.yml` (see `config.example.yml`) and use it for setup, start, stop, and remove.

## Prerequisites

- A [Cloudflare](https://cloudflare.com) account.
- **Ruby** (stdlib YAML) or **Python 3** with PyYAML — used by the scripts to parse `config.yml`. On the server, **cloudflared** can be installed by the setup script if missing.
- The hostnames in your config must use zones in the Cloudflare account you log in with.

## Quick start (with these scripts)

1. **Copy and edit the config:**

   ```bash
   cp config.example.yml config.yml
   # Edit config.yml: set tunnel name, hostname, and local service URL for each tunnel.
   ```

2. **Run setup** (installs cloudflared if needed, logs in via browser link, creates each tunnel, routes DNS, installs systemd services):

   ```bash
   ./setup_cloudflare_tunnel.sh config.yml
   ```

   When prompted, open the URL in your browser to authorize the account. Each tunnel gets its own UUID and a systemd unit `cloudflared-<name>.service` that auto-starts on boot.

3. **Start / stop / remove** (all read the same config):

   ```bash
   ./start_cloudflaretunnel.sh config.yml
   ./stop_cloudflare_tunnel.sh config.yml
   ./remove_cloudflare_tunnel.sh config.yml
   ```

## Config file format

`config.yml` has a single top-level key **`tunnels`**: a list of entries, each with:

| Key         | Description |
|------------|-------------|
| `name`     | Tunnel name (used for CLI and for the systemd unit `cloudflared-<name>.service`). |
| `hostname` | Public hostname in your Cloudflare zone (e.g. `app.example.com`). |
| `service`  | Local service URL (e.g. `http://localhost:3000`). |

Example:

```yaml
tunnels:
  - name: my-app
    hostname: app.example.com
    service: http://localhost:3000
  - name: my-api
    hostname: api.example.com
    service: http://localhost:8080
```

## What each script does

| Script | Usage | Description |
|--------|--------|-------------|
| **setup_cloudflare_tunnel.sh** | `./setup_cloudflare_tunnel.sh config.yml` | 1) Install cloudflared if missing. 2) One-time login via `cloudflared tunnel login`. 3) For each tunnel in config: create tunnel, write per-tunnel config under `~/.cloudflared/`, route DNS. 4) Install and enable one systemd service per tunnel so they auto-start. |
| **start_cloudflaretunnel.sh** | `./start_cloudflaretunnel.sh config.yml` | Starts all `cloudflared-<name>.service` units listed in the config. |
| **stop_cloudflare_tunnel.sh** | `./stop_cloudflare_tunnel.sh config.yml` | Stops all tunnel services from the config. |
| **remove_cloudflare_tunnel.sh** | `./remove_cloudflare_tunnel.sh config.yml` | Stops and disables each tunnel service, deletes each tunnel via CLI, removes per-tunnel config and credentials. DNS CNAMEs are left in Cloudflare (remove in dashboard if desired). |
| **clean_cloudflare_tunnel.sh** | `./clean_cloudflare_tunnel.sh [USER]` | **No config.** This host only: stops/disables cloudflared services, kills cloudflared processes, removes local config and credential files. Does **not** delete any tunnels from your Cloudflare account. To delete tunnels use remove with config. |

All setup/start/stop/remove scripts **read the config** to get tunnel names (and for setup: hostname and service). Use the same `config.yml` for setup, start, stop, and remove.

## Directory layout

```
cloudflare-tools/
├── README.md
├── config.example.yml   # Example config; copy to config.yml and edit
├── setup_cloudflare_tunnel.sh
├── start_cloudflaretunnel.sh
├── stop_cloudflare_tunnel.sh
├── remove_cloudflare_tunnel.sh
└── clean_cloudflare_tunnel.sh   # no config: wipes all tunnels and processes
```

- **config.example.yml** — Copy to `config.yml`, set your tunnel names, hostnames, and local service URLs. Used by all four scripts.
- Setup writes per-tunnel configs to `~/.cloudflared/config-<name>.yml` and credentials to `~/.cloudflared/<TUNNEL_UUID>.json`. Systemd units are installed under `/etc/systemd/system/cloudflared-<name>.service`.

## Manual CLI reference

If you prefer to run cloudflared by hand:

- **Log in (one-time):** `cloudflared tunnel login`
- **Create tunnel:** `cloudflared tunnel create <name>`
- **Route DNS:** `cloudflared tunnel route dns <name> <hostname>`
- **Run tunnel:** `cloudflared tunnel run <name>` or `cloudflared tunnel --config <path> run`
- **Install as service:** after config is in place, `sudo cloudflared service install` (single default tunnel). These scripts instead create one systemd unit per tunnel.

## References

- [Cloudflare Tunnels (Connect)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Install cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/)
- [Configure a tunnel (config.yml)](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/local/)
- [Route DNS](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/local/#route-cloudflare-tunnel-traffic-to-a-dns-record)

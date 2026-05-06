# Installation

This document provides a short installation path and points to the full deployment guides in the repository.

## Supported platforms

Fail2Ban UI targets Linux hosts. Typical environments include RHEL/Rocky/Alma, Debian/Ubuntu, and container environments in general.

## Container deployment

Additional resources:
- Full guide: `deployment/container/README.md`
- SELinux policies: `deployment/container/SELinux/`

### Option A: Pre-built image

Local connector example (Fail2Ban runs on the same host):
```bash
podman pull swissmakers/fail2ban-ui:latest

podman run -d --name fail2ban-ui --network=host \
  -v /opt/fail2ban-ui:/config:Z \
  -v /etc/fail2ban:/etc/fail2ban:Z \
  -v /var/run/fail2ban:/var/run/fail2ban \
  -v /var/log:/var/log:ro \
  swissmakers/fail2ban-ui:latest
````

Notes:

* `/config` stores the SQLite DB, settings, and SSH keys used by the UI.
* `/var/log` is used for log path tests and should be mounted read-only to the container.

### Option B: Docker Compose

Use one of the examples and adapt to your environment:

```bash
cp docker-compose.example.yml docker-compose.yml
# or
cp docker-compose-allinone.example.yml docker-compose.yml

podman compose up -d
```

You can also run the development stacks under `development/` if you want to evaluate features first.

### Option C: Build the image yourself

```bash
git clone https://github.com/swissmakers/fail2ban-ui.git
cd fail2ban-ui
podman build -t fail2ban-ui:dev .
podman run -d --name fail2ban-ui --network=host \
  -v /opt/fail2ban-ui:/config:Z \
  -v /etc/fail2ban:/etc/fail2ban:Z \
  -v /var/run/fail2ban:/var/run/fail2ban \
  -v /var/log:/var/log:ro \
  localhost/fail2ban-ui:dev
```

## systemd deployment (standalone)

Additional resources:

* Full guide: `deployment/systemd/README.md`
* SELinux and Fail2Ban -> UI HTTP callbacks: [`docs/security.md`](https://github.com/swissmakers/fail2ban-ui/blob/main/docs/security.md#selinux) (often `setsebool -P nis_enabled 1` on RHEL-family hosts)

### Option A: Automated installer (Ubuntu/Debian — recommended)

The bundled `install.sh` script handles all prerequisites, builds the binary, configures the database, and installs a systemd service in one guided session:

```bash
git clone https://github.com/swissmakers/fail2ban-ui.git /opt/fail2ban-ui
cd /opt/fail2ban-ui
sudo ./install.sh
```

The installer prompts you for:

1. **Install directory** — where to place the binary and source (default `/opt/fail2ban-ui`)
2. **Database** — SQLite (no setup needed) or PostgreSQL (connection details configured interactively)
3. **Listen port and bind address** — defaults to `8080` / `127.0.0.1`
4. **Callback URL** — the public URL fail2ban hosts will POST ban events to
5. **OIDC** — optionally configure an OIDC provider for single sign-on
6. **Service user** — which OS user the service runs as

On completion the installer:
- Writes a config file to `/etc/fail2ban-ui/fail2ban-ui.env` (mode `0600`)
- Registers and starts `fail2ban-ui.service` via systemd

To update a deployment installed this way, run:

```bash
sudo /opt/fail2ban-ui/update.sh
```

### Option B: Manual build

```bash
git clone https://github.com/swissmakers/fail2ban-ui.git /opt/fail2ban-ui
cd /opt/fail2ban-ui

# Build static CSS assets
./build-tailwind.sh

# Build the Go binary (embeds pkg/web/templates, pkg/web/locales, and pkg/web/static)
go build -o fail2ban-ui ./cmd/server/main.go
```

Then follow `deployment/systemd/README.md` to install the unit file and configure permissions.

## Production recommendation

For production deployments:

- Enable OIDC if your environment supports centralized identity.
- Keep the UI behind a reverse proxy (TLS termination + access controls).
- Bind the UI to loopback (`BIND_ADDRESS=127.0.0.1`) when proxy and app share the host.

Reference: [`docs/reverse-proxy.md`](https://github.com/swissmakers/fail2ban-ui/blob/main/docs/reverse-proxy.md).


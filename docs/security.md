# Security guidance

This project can perform security-sensitive operations (bans, configuration changes). Deploy it as you would deploy every other administrative interface.

## Recommended deployment posture

- Do not expose the UI directly to the Internet.
- Prefer one of:
  - VPN-only access
  - Reverse proxy with strict allowlists
  - OIDC enabled (in addition to network controls)

If you must publish it, put it behind TLS and an authentication layer, and restrict source IPs.

See [`docs/reverse-proxy.md`](https://github.com/swissmakers/fail2ban-ui/blob/main/docs/reverse-proxy.md) for hardened proxy examples and WebSocket forwarding requirements.

## Input validation

All user-supplied IP addresses are validated using Go's `net.ParseIP` and `net.ParseCIDR` before they are passed to any integration, command, or database query. This applies to:

- Ban/Unban callbacks (`/api/ban`, `/api/unban`)
- Manual ban/unban actions from the dashboard
- Advanced action test endpoint (`/api/advanced-actions/test`)
- All integration connectors (MikroTik, pfSense, OPNsense)

Integration-specific identifiers (address list names, alias names) are validated against a strict alphanumeric pattern (`[a-zA-Z0-9._-]`) to prevent injection in both SSH commands and API payloads.

## WebSocket security

The WebSocket endpoint (`/api/ws`) is protected by:

- **Origin validation**: The upgrade handshake verifies that the `Origin` header matches the request's `Host` header (same-origin policy). Cross-origin WebSocket connections are rejected. This prevents cross-site WebSocket hijacking attacks.
- **Authentication**: When OIDC is enabled, the WebSocket endpoint requires a valid session.

## Callback endpoint protection

The callback endpoints (`/api/ban`, `/api/unban`) are protected by `CALLBACK_SECRET` (`X-Callback-Secret` header). If no secret is specified, Fail2Ban UI generates one on first start. Additional hardening:

- Use a long, random secret and rotate it on suspected leakage
- Restrict network access so only known Fail2Ban hosts can reach callback endpoints

Rotate the secret if you suspect leakage.

## SSH connector hardening

For SSH-managed hosts:

- Use a dedicated service account (not a human user).
- Require key-based auth.
- Restrict sudo to the minimum set of commands required to operate Fail2Ban (at minimum `fail2ban-client *` and `systemctl restart fail2ban`).
- Use filesystem ACLs for `/etc/fail2ban` rather than broad permissions to allow full modification capabilities for the specific user.

### SSH host key verification

Fail2Ban UI uses `StrictHostKeyChecking=accept-new` for all SSH-managed hosts. This means:

- **First connection**: the remote host's key is accepted automatically and saved to the known-hosts file. No manual approval is required.
- **Subsequent connections**: the saved key is verified. If the key has changed (e.g. host was re-imaged, or a MITM is in path), the connection is **rejected** and an error is logged.

The known-hosts file location is resolved in this order:

1. `SSH_KNOWN_HOSTS` environment variable (if set)
2. `~/.ssh/known_hosts` (home directory of the user running Fail2Ban UI)

To pre-trust a host before first use, add its key manually:

```bash
ssh-keyscan -H <host> >> ~/.ssh/known_hosts
```

To re-trust a host after a key change (e.g. you rebuilt it intentionally):

```bash
ssh-keygen -R <host> -f ~/.ssh/known_hosts
# then let Fail2Ban UI reconnect — the new key will be accepted and saved
```

## Integration connector hardening

When using external firewall integrations (MikroTik, pfSense, OPNsense):

- Use a dedicated service account on the firewall device with the minimum permissions needed (address-list management only on MikroTik; alias management only on pfSense/OPNsense).
- For pfSense/OPNsense: use a dedicated API token with limited scope.
- Restrict network access so the Fail2ban-UI host is the only source allowed to reach the firewall management interface.

### MikroTik SSH host key verification (TOFU)

The MikroTik integration connects over SSH. On first use it performs **Trust On First Use (TOFU)**:

1. The remote host's SSH key fingerprint (SHA-256) is accepted automatically and saved to the `HostFingerprint` field in Settings.
2. All subsequent connections verify the live fingerprint against the saved value. A mismatch aborts the connection and logs an error — this prevents silent man-in-the-middle attacks against the router management channel.

**To reset after a deliberate key change** (e.g. you reset the router):  
Go to **Settings → Advanced Actions → Mikrotik** and clear the `HostFingerprint` field, then save. The next connection will re-learn and save the new key.

## Least privilege and file access

Local connector deployments typically require access to:
- `/var/run/fail2ban/fail2ban.sock`
- `/etc/fail2ban/`
- selected log paths (read-only, mounted to same place inside the container, where they are on the host.)

Avoid running with more privileges than necessary. If you run in a container, use the repository deployment guide and, where needed, the optional container SELinux modules.

## SELinux

Do not disable SELinux as a shortcut. Fix labeling, booleans, and policy issues instead.

### Fail2Ban ban/unban callbacks (`curl` from `fail2ban_t`)

The UI installs an action that runs `curl` from the Fail2Ban service context to reach `/api/ban` and `/api/unban`. With SELinux enforcing, you may see denials such as `curl` / `fail2ban_t` / `name_connect` / `tcp_socket` / `http_port_t` (for example when the callback URL uses HTTPS on port 443).

On RHEL-family systems, `setroubleshoot` typically recommends enabling the **`nis_enabled`** boolean, which allows this class of outbound connection:

```bash
sudo setsebool -P nis_enabled 1
```

Prefer that over ad-hoc `audit2allow` modules unless your organization requires a different control.

### Container ↔ host Fail2Ban (optional modules)

If the UI runs in Podman/Docker with a **local** connector, extra rules can be needed so `container_t` can use the Fail2Ban socket and read the right logs (not the same problem as the callback boolean above). Sources and build steps are in `deployment/container/SELinux/`.

## Alert provider security

Fail2Ban UI supports three alert providers: Email (SMTP), Webhook, and Elasticsearch. Each has specific security considerations.

### Email (SMTP)

- Use TLS (`Use TLS` enabled) for all SMTP connections.
- Avoid disabling TLS verification (`Skip TLS Verification`) in production. If you must, ensure the network path to the SMTP server is trusted.
- Use application-specific passwords or OAuth tokens where supported (e.g. Gmail, Office365) instead of primary account passwords.

### Webhook

- Use HTTPS endpoints whenever possible.
- If the webhook endpoint requires authentication, use custom headers (e.g. `Authorization: Bearer <token>`) rather than embedding credentials in the URL.
- Avoid disabling TLS verification for production endpoints. The `Skip TLS Verification` option exists for development/self-signed environments only.

### Elasticsearch

- Use API key authentication over basic auth when possible. API keys can be scoped to specific indices and rotated independently.
- Restrict the API key to write-only access on the `fail2ban-events-*` index pattern. Avoid cluster-wide or admin-level keys.
- Consider using Elasticsearch's built-in role-based access control to limit what the Fail2Ban UI service account can do.


## Rate limiting

Fail2Ban UI enforces per-source-IP rate limits on endpoints that are either externally reachable or sensitive:

| Endpoint | Limit | Rationale |
|---|---|---|
| `POST /api/ban`, `POST /api/unban` | 60 requests / minute | Public callback endpoints — limits abuse from compromised or misconfigured hosts |
| `GET /auth/login`, `GET /auth/callback` | 10 requests / minute | Limits OIDC login enumeration and token-endpoint hammering |

Requests that exceed the limit receive `HTTP 429 Too Many Requests`. The limit resets automatically (token bucket — capacity refills at 1 token/second for callbacks, and ~1 token/6s for auth endpoints).

## CSRF protection

All authenticated, mutating API requests (any method other than GET, HEAD, or OPTIONS on a non-public route) must include the header:

```
X-Requested-With: XMLHttpRequest
```

The built-in JavaScript API helper (`serverHeaders()`) sets this header automatically on every request from the browser UI. Third-party API clients and scripts that call authenticated endpoints must add the header manually.

The following paths are exempt (they use their own auth mechanism):

- `/api/ban`, `/api/unban` — protected by `X-Callback-Secret`
- `/api/healthcheck/callback` — protected by `X-Callback-Secret`
- `/auth/*` — OIDC flow endpoints

A missing header returns `HTTP 403 Forbidden`.

## Credential encryption at rest

When the `ENCRYPTION_KEY` environment variable is set, all credentials stored in the database are encrypted with **AES-256-GCM** before being written and decrypted on read. The following fields are covered:

- Callback secret
- SMTP password
- Advanced Actions config (MikroTik password, pfSense API token, OPNsense API key/secret, Vision One API token)
- Webhook, Elasticsearch, and Threat Intelligence API keys/passwords
- Per-server agent secrets

Encrypted values are stored with an `enc:` prefix so they can be distinguished from plaintext during migration.

**Setup:**

```bash
# Generate a 32-byte random key as a 64-character hex string:
openssl rand -hex 32
# → e.g. a3f1...c9d2

# Set it in your environment file:
ENCRYPTION_KEY=a3f1...c9d2
```

**Migration from plaintext:** existing plaintext rows are read correctly on startup. On the next settings save, all credentials are re-written as encrypted. No manual data migration is required.

**Key rotation:** update `ENCRYPTION_KEY` and then resave settings in the UI — this re-encrypts all credentials under the new key.

> If `ENCRYPTION_KEY` is removed after credentials have been encrypted, startup will log decrypt warnings and the raw `enc:...` ciphertext will be used as the value — effectively breaking those integrations. Always keep a backup of the key alongside your database backup.

## Audit and operational practices

- Back up `/config` (DB + settings) regularly.
- Treat the database as sensitive operational data.
- Keep the host and container runtime patched.
- Review Fail2Ban actions deployed to managed hosts as part of change control.
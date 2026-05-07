# Advanced Action Integrations

Fail2Ban UI can push blocked IPs to external security platforms in addition to (or instead of) local Fail2ban banning. These are called **Advanced Actions** and are configured in **Settings → Advanced Actions**.

When an Advanced Action is enabled, every ban event processed by the UI is also forwarded to the configured platform. Unbans trigger the corresponding removal call.

---

## Mikrotik

Adds and removes IPs from a Mikrotik router's Address List via the RouterOS REST API.

### Prerequisites

- Mikrotik RouterOS v7.1 or later (REST API required)
- A dedicated API user account on the router

### Step-by-step setup

**1. Create an API user on the router**

Open the Mikrotik WebFig or Winbox, go to **System → Users**, and add a user with `api` and `read/write` permissions. Note the username and password.

**2. Enable the REST API**

In RouterOS, the REST API is enabled by default on port 80 (HTTP) or 443 (HTTPS) via the router's web server. Confirm it is running under **IP → Services** — `www` (80) or `www-ssl` (443) must be enabled.

**3. Configure in Fail2Ban UI**

Go to **Settings → Advanced Actions**, select **Mikrotik**, and fill in:

| Field | Description |
|---|---|
| Host | Router IP address or hostname (e.g. `192.168.1.1`) |
| Port | REST API port — `80` for HTTP, `443` for HTTPS |
| Username | API user created in step 1 |
| Password | API user password |
| Address List Name | Name of the Address List to add blocked IPs to (e.g. `fail2ban-blocked`) |
| Use HTTPS | Enable when connecting to the router over HTTPS |
| Skip TLS Verification | Disable certificate validation (safe for self-signed certs on LAN, not recommended over internet) |

**4. Save and test**

Click **Save**. Trigger a manual ban from the UI and verify the IP appears in **IP → Firewall → Address Lists** on the router.

---

## pfSense

Adds and removes IPs from a pfSense firewall alias via the pfSense API (fauxapi or REST).

### Prerequisites

- pfSense 2.5+ with [pfSense API](https://github.com/jaredhendrickson13/pfsense-api) installed, OR pfSense Plus 23.09+ with the built-in REST API enabled
- An API key with firewall alias write permission

### Step-by-step setup

**1. Install the pfSense API package**

In pfSense, go to **System → Package Manager → Available Packages** and install `pfSense-pkg-API`. After installation, navigate to **System → API** to configure it.

**2. Create an API key**

Under **System → API → Keys**, create a new key. Copy the key and secret — you will need them in the next step.

**3. Configure in Fail2Ban UI**

Go to **Settings → Advanced Actions**, select **pfSense**, and fill in:

| Field | Description |
|---|---|
| Host | pfSense IP address or hostname |
| Port | Port for the pfSense web interface (typically `443`) |
| API Key | Key created in step 2 |
| API Secret | Secret created in step 2 |
| Alias Name | Firewall alias to add IPs to (create it in pfSense under **Firewall → Aliases** first) |
| Skip TLS Verification | Disable certificate check for self-signed certs |

**4. Create the firewall alias**

In pfSense, go to **Firewall → Aliases → IP**, create an alias (e.g. `fail2ban_blocked`) of type **Host(s)**. Then reference this alias in a block rule under **Firewall → Rules**.

---

## OPNsense

Adds and removes IPs from an OPNsense firewall alias via the OPNsense API.

### Prerequisites

- OPNsense 23.1 or later
- An API key with `firewall` access

### Step-by-step setup

**1. Create an API key**

In OPNsense, go to **System → Access → Users**, edit your admin user (or create a dedicated one), scroll to **API Keys**, and click **+** to generate a new key+secret pair. Download the credentials file.

**2. Configure in Fail2Ban UI**

Go to **Settings → Advanced Actions**, select **OPNsense**, and fill in:

| Field | Description |
|---|---|
| Host | OPNsense IP or hostname |
| Port | API port (default `443`) |
| API Key | Key from the downloaded credentials |
| API Secret | Secret from the downloaded credentials |
| Alias Name | Firewall alias to add IPs to |
| Skip TLS Verification | Disable certificate check for self-signed certs |

**3. Create the alias and rule**

In OPNsense, go to **Firewall → Aliases**, add an alias of type **Host(s)** (e.g. `fail2ban_blocked`). Then in **Firewall → Rules**, create a block rule referencing this alias as the source.

---

## Trend Micro Vision One

Adds blocked IPs to Trend Micro Vision One's **Suspicious Objects** list via the Vision One v3 API. Vision One then automatically applies detection/block actions across endpoints, email gateways, and network sensors enrolled in your tenant.

### How it works

Vision One is **not** called directly by Fail2ban. The full chain is:

```
Fail2ban (ban event)
  → action script on the Fail2ban host fires a curl callback
    → Fail2ban-UI receives POST /api/ban
      → Fail2ban-UI evaluates the threshold
        → Fail2ban-UI calls the Vision One API
```

The action script's only job is to notify Fail2ban-UI that a ban occurred. Fail2ban-UI holds the Vision One API token and makes the API call. This means:

- The action script must be deployed to **every Fail2ban host** you want covered.
- Fail2ban-UI must be reachable from those hosts at the configured callback URL.
- Vision One is only contacted **after the ban count for an IP reaches the configured threshold** — it does not fire on every ban.

### Prerequisites

- An active Trend Micro Vision One tenant
- An API key with **Threat Intelligence** write permission (specifically the `Suspicious Object Management` API scope)
- The Fail2ban action script deployed and Fail2ban reloaded on every managed host (see Step 5 below)

### Step-by-step setup

**1. Generate an API key**

Log into Vision One and navigate to **Administration → API Keys**. Click **Add API Key**, give it a descriptive name (e.g. `fail2ban-ui`), set the role to **Master Administrator** or a custom role that includes the `Suspicious Object Management` scope with write access. Copy the token — it is shown only once.

**2. Identify your region**

Your Vision One region matches the data residency of your tenant. Check the URL in your browser when logged into Vision One:

| URL domain | Region code |
|---|---|
| `portal.xdr.trendmicro.com` | `us` |
| `portal.eu.xdr.trendmicro.com` | `eu` |
| `portal.xdr.trendmicro.co.jp` | `jp` |
| `portal.sg.xdr.trendmicro.com` | `sg` |
| `portal.in.xdr.trendmicro.com` | `in` |
| `portal.au.xdr.trendmicro.com` | `au` |

**3. Configure in Fail2Ban UI**

Go to **Settings → Advanced Actions**, select **Trend Micro Vision One**, and fill in:

| Field | Description |
|---|---|
| Enabled | Must be toggled **on** — the integration does nothing when disabled |
| Region | Your tenant's region code (see table above) |
| API Token | The token generated in step 1 |
| Threshold | Number of times an IP must be banned before Vision One is called. `1` = every ban triggers it; `5` = only repeat offenders. |
| Risk Level | Severity assigned to each blocked IP: `high`, `medium`, or `low`. Defaults to `high`. |
| Days to Expiration | How many days until Vision One automatically removes the entry. Set to `0` for no expiry. |
| Description | Label stored with each Suspicious Object entry (e.g. `Blocked by Fail2ban`) |
| Skip TLS Verification | Disable certificate check — leave unchecked in production |

**4. Save settings**

Click **Save**. The integration will not fire until the action script is also deployed (next step).

**5. Deploy the action script to each Fail2ban host**

The action script is a small conf file that Fail2ban runs on every ban/unban to notify Fail2ban-UI. It must exist on the **Fail2ban host**, not on the Fail2ban-UI host.

Go to **Settings → Manage Servers**, find the server you want to cover, and click **Deploy action script**. Fail2ban-UI will:

1. Write `/etc/fail2ban/action.d/ui-custom-action.conf` on that host (via SSH for remote servers, directly for local servers)
2. Write `/etc/fail2ban/jail.local` to reference the action (skipped if a user-managed `jail.local` already exists — see note below)

After deploying, **restart Fail2ban on that host** — `reload` is not sufficient when deploying the action file for the first time:

```bash
sudo systemctl restart fail2ban
```

> **SSH server permission requirement:** The SSH user configured for the server must have write access to `/etc/fail2ban/action.d/` and `/etc/fail2ban/jail.local` on the remote host. If the deploy fails with a permission error, run the following on the remote host:
> ```bash
> sudo chown root:<ssh-user-group> /etc/fail2ban/action.d
> sudo chmod g+w /etc/fail2ban/action.d
> sudo chown root:<ssh-user-group> /etc/fail2ban/jail.local
> sudo chmod g+w /etc/fail2ban/jail.local
> ```

> **User-managed jail.local:** If `/etc/fail2ban/jail.local` already exists and was not created by Fail2ban-UI, it will not be overwritten. You must manually add the following to the `[DEFAULT]` section and restart Fail2ban:
> ```ini
> action_mwlg = %(action_)s
>              ui-custom-action[logpath="%(logpath)s", chain="%(chain)s"]
> action = %(action_mwlg)s
> ```

> **Per-jail action override:** If any jail in `/etc/fail2ban/jail.d/` has its own `action =` line, it overrides `[DEFAULT]` for that jail and the callback will not fire. Check for overrides with:
> ```bash
> grep -rn "^\s*action\s*=" /etc/fail2ban/jail.d/
> ```
> For each affected jail, add `ui-custom-action` explicitly inside that jail's section:
> ```ini
> [your-jail-name]
> action = %(action_)s
>          ui-custom-action[logpath="%(logpath)s", chain="%(chain)s"]
> ```

**6. Verify end-to-end**

Trigger a test ban that will meet the configured threshold. In Vision One, go to **Threat Intelligence → Suspicious Object Management** and confirm the IP appears.

To see Vision One API calls in the Fail2ban-UI logs, enable **Debug mode** in **Settings → General**. You will then see log lines like:

```
Vision One API POST https://api.au.xdr.trendmicro.com/v3.0/threatintel/suspiciousObjects payload=[...]
Vision One: IP 1.2.3.4 added to Suspicious Objects list (region: au)
```

Without debug mode, Vision One calls are silent in the logs unless they fail.

### Behaviour notes

- Vision One is only called once per IP per integration — if the IP is already permanently blocked, subsequent bans do not re-send it.
- Bans → IP added via `POST /v3.0/threatintel/suspiciousObjects`
- Unbans → IP removed via `DELETE /v3.0/threatintel/suspiciousObjects`
- If the IP already exists in the list when a ban fires, Vision One returns `409 Conflict` — the integration treats this as success (no duplicate error).
- The Vision One API returns HTTP 207 Multi-Status; per-item errors are checked and surfaced as failures.
- The block history (including errors) is visible in **Settings → Advanced Actions → Block History**.

### API reference

Full Vision One API documentation: <https://automation.trendmicro.com/xdr/api-v3>

---

## General notes

- Only one Advanced Action can be active at a time.
- Advanced Actions fire **in addition to** the local fail2ban ban — they do not replace it.
- Errors from Advanced Action calls are logged but do not block the ban event from being recorded.
- All credentials are stored in the application database (encrypted at rest if your database supports it).

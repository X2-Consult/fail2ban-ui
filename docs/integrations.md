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

### Prerequisites

- An active Trend Micro Vision One tenant
- An API key with **Threat Intelligence** write permission (specifically the `Suspicious Object Management` API scope)

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
| Region | Your tenant's region code (see table above) |
| API Token | The token generated in step 1 |
| Risk Level | Severity assigned to each blocked IP: `high`, `medium`, or `low`. Defaults to `high`. |
| Days to Expiration | How many days until Vision One automatically removes the entry. Set to `0` for no expiry. |
| Description | Label stored with each Suspicious Object entry (e.g. `Blocked by Fail2ban-UI`) |
| Skip TLS Verification | Disable certificate check — leave unchecked in production |

**4. Save and verify**

Click **Save**. Trigger a manual ban from the Fail2Ban UI dashboard. In Vision One, go to **Threat Intelligence → Suspicious Object Management** and confirm the IP appears in the list.

**Behaviour notes:**

- Bans → IP added via `POST /v3.0/threatintel/suspiciousObjects`
- Unbans → IP removed via `DELETE /v3.0/threatintel/suspiciousObjects`
- If the IP already exists in the list when a ban fires, Vision One returns `409 Conflict` — the integration treats this as success (no duplicate error)
- The Vision One API returns HTTP 207 Multi-Status; per-item errors are checked and surfaced as failures

### API reference

Full Vision One API documentation: <https://automation.trendmicro.com/xdr/api-v3>

---

## General notes

- Only one Advanced Action can be active at a time.
- Advanced Actions fire **in addition to** the local fail2ban ban — they do not replace it.
- Errors from Advanced Action calls are logged but do not block the ban event from being recorded.
- All credentials are stored in the application database (encrypted at rest if your database supports it).

#!/bin/bash
# Fail2ban-UI Installer
# Supports Ubuntu/Debian. Run as root or with sudo.

set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ─── Root check ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Please run as root: sudo ./install.sh"

# ─── Banner ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        Fail2ban-UI  Installer            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ─── Helper: prompt with default ────────────────────────────────────────────
prompt() {
    local var="$1" msg="$2" default="$3"
    read -rp "$(echo -e "${BOLD}${msg}${NC} [${default}]: ")" val
    eval "$var=\"${val:-$default}\""
}

prompt_secret() {
    local var="$1" msg="$2"
    read -rsp "$(echo -e "${BOLD}${msg}${NC}: ")" val
    echo ""
    eval "$var=\"$val\""
}

# ─── Step 1: Install directory ──────────────────────────────────────────────
echo -e "${BOLD}── Installation ──────────────────────────────────────────────${NC}"
prompt INSTALL_DIR "Install directory" "/opt/fail2ban-ui"
INSTALL_DIR="${INSTALL_DIR%/}"    # strip trailing slash
CONFIG_DIR="/etc/fail2ban-ui"
ENV_FILE="$CONFIG_DIR/fail2ban-ui.env"
SERVICE_FILE="/etc/systemd/system/fail2ban-ui.service"
INSTALL_CONF="$CONFIG_DIR/installer.conf"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# ─── Step 2: Clone or pull ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Source code ───────────────────────────────────────────────${NC}"
if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Existing git repo found at $INSTALL_DIR — skipping clone."
else
    # Check if the current directory IS the repo (user ran from the cloned dir)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/go.mod" && "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        info "Copying source from $SCRIPT_DIR → $INSTALL_DIR"
        cp -a "$SCRIPT_DIR/." "$INSTALL_DIR/"
    elif [[ -f "$INSTALL_DIR/go.mod" ]]; then
        info "Source already present at $INSTALL_DIR."
    else
        prompt REPO_URL "Git repository URL" "git@github.com:X2-Consult/fail2ban-ui.git"
        info "Cloning $REPO_URL → $INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
fi

cd "$INSTALL_DIR"

# ─── Step 3: Prerequisites ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Prerequisites ─────────────────────────────────────────────${NC}"

# Go
if ! command -v go &>/dev/null; then
    warn "Go is not installed."
    read -rp "$(echo -e "${BOLD}Install Go via snap? [Y/n]: ${NC}")" install_go
    if [[ "${install_go,,}" != "n" ]]; then
        info "Installing Go via snap..."
        snap install go --classic
        export PATH="$PATH:/snap/bin"
        success "Go installed: $(go version)"
    else
        die "Go is required to build fail2ban-ui. Please install it manually."
    fi
else
    success "Go: $(go version)"
fi

# Node / npm
if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
    warn "Node.js / npm not found."
    read -rp "$(echo -e "${BOLD}Install Node.js 20 via apt? [Y/n]: ${NC}")" install_node
    if [[ "${install_node,,}" != "n" ]]; then
        info "Installing Node.js 20..."
        apt-get install -y ca-certificates curl gnupg
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
            | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
            > /etc/apt/sources.list.d/nodesource.list
        apt-get update -q
        apt-get install -y nodejs
        success "Node.js: $(node --version), npm: $(npm --version)"
    else
        warn "Skipping Node.js. Tailwind CSS will not be rebuilt."
        SKIP_TAILWIND=1
    fi
else
    success "Node.js: $(node --version), npm: $(npm --version)"
fi

# ─── Step 4: Database choice ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Database ──────────────────────────────────────────────────${NC}"
echo "  1) SQLite  (default, no extra setup)"
echo "  2) PostgreSQL"
read -rp "$(echo -e "${BOLD}Choose database [1]: ${NC}")" db_choice
db_choice="${db_choice:-1}"

DB_TYPE="sqlite"
DATABASE_URL=""

if [[ "$db_choice" == "2" ]]; then
    DB_TYPE="postgres"
    echo ""
    info "PostgreSQL selected."
    prompt PG_HOST     "PostgreSQL host"     "localhost"
    prompt PG_PORT     "PostgreSQL port"     "5432"
    prompt PG_DBNAME   "Database name"       "fail2ban_ui"
    prompt PG_USER     "Database user"       "fail2ban_ui"
    prompt_secret PG_PASS "Password for '$PG_USER'"

    # Offer to create DB + user
    echo ""
    read -rp "$(echo -e "${BOLD}Create the database and user now? (requires local postgres superuser) [Y/n]: ${NC}")" create_db
    if [[ "${create_db,,}" != "n" ]]; then
        info "Creating PostgreSQL user '$PG_USER' and database '$PG_DBNAME'..."
        sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$PG_USER') THEN
        CREATE ROLE "$PG_USER" LOGIN PASSWORD '$PG_PASS';
        RAISE NOTICE 'Created role $PG_USER';
    ELSE
        ALTER ROLE "$PG_USER" PASSWORD '$PG_PASS';
        RAISE NOTICE 'Updated password for existing role $PG_USER';
    END IF;
END
\$\$;
SELECT 'CREATE DATABASE' WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = '$PG_DBNAME'
)\gexec
GRANT ALL PRIVILEGES ON DATABASE "$PG_DBNAME" TO "$PG_USER";
ALTER DATABASE "$PG_DBNAME" OWNER TO "$PG_USER";
SQL
        success "PostgreSQL database '$PG_DBNAME' ready."
    fi

    PG_SSLMODE="disable"
    if [[ "$PG_HOST" != "localhost" && "$PG_HOST" != "127.0.0.1" ]]; then
        PG_SSLMODE="require"
    fi
    DATABASE_URL="postgres://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DBNAME}?sslmode=${PG_SSLMODE}"
    success "DATABASE_URL configured."
fi

# ─── Step 5: App config ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Application settings ──────────────────────────────────────${NC}"
prompt APP_PORT         "Listen port"                          "8080"
prompt APP_BIND         "Bind address"                         "127.0.0.1"
prompt CALLBACK_URL     "Public callback URL (for fail2ban action)" "http://localhost:${APP_PORT}"
CALLBACK_SECRET="$(openssl rand -hex 32)"
success "Callback secret auto-generated."

# OIDC (optional)
OIDC_ENABLED="false"
read -rp "$(echo -e "${BOLD}Enable OIDC authentication? [y/N]: ${NC}")" enable_oidc
if [[ "${enable_oidc,,}" == "y" ]]; then
    OIDC_ENABLED="true"
    prompt OIDC_PROVIDER     "OIDC provider (keycloak/authentik/pocket-id)" "keycloak"
    prompt OIDC_ISSUER_URL   "OIDC issuer URL"   ""
    prompt OIDC_CLIENT_ID    "OIDC client ID"    "fail2ban-ui"
    prompt_secret OIDC_CLIENT_SECRET "OIDC client secret"
    prompt OIDC_REDIRECT_URL "OIDC redirect URL" "${CALLBACK_URL}/auth/callback"
fi

# ─── Step 6: Write env file ─────────────────────────────────────────────────
echo ""
info "Writing environment file → $ENV_FILE"
cat > "$ENV_FILE" <<EOF
# Fail2ban-UI environment — managed by installer
# Edit and run update.sh to apply changes.

PORT=$APP_PORT
BIND_ADDRESS=$APP_BIND
CALLBACK_URL=$CALLBACK_URL
CALLBACK_SECRET=$CALLBACK_SECRET

DB_TYPE=$DB_TYPE
$(if [[ -n "$DATABASE_URL" ]]; then echo "DATABASE_URL=$DATABASE_URL"; fi)

OIDC_ENABLED=$OIDC_ENABLED
$(if [[ "$OIDC_ENABLED" == "true" ]]; then
    echo "OIDC_PROVIDER=$OIDC_PROVIDER"
    echo "OIDC_ISSUER_URL=$OIDC_ISSUER_URL"
    echo "OIDC_CLIENT_ID=$OIDC_CLIENT_ID"
    echo "OIDC_CLIENT_SECRET=$OIDC_CLIENT_SECRET"
    echo "OIDC_REDIRECT_URL=$OIDC_REDIRECT_URL"
fi)
EOF
chmod 600 "$ENV_FILE"
success "Env file written."

# ─── Step 7: Build Tailwind CSS ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Building Tailwind CSS ─────────────────────────────────────${NC}"
if [[ "${SKIP_TAILWIND:-0}" != "1" ]]; then
    bash "$INSTALL_DIR/build-tailwind.sh"
else
    warn "Skipping Tailwind build (Node.js not available)."
fi

# ─── Step 8: Fetch Go dependencies ──────────────────────────────────────────
echo ""
echo -e "${BOLD}── Fetching Go dependencies ──────────────────────────────────${NC}"
cd "$INSTALL_DIR"
go mod tidy
success "Go modules resolved."

# ─── Step 9: Build binary ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Building binary ───────────────────────────────────────────${NC}"
CGO_ENABLED=0 go build -ldflags="-s -w" -o "$INSTALL_DIR/fail2ban-ui" ./cmd/server/main.go
success "Binary built → $INSTALL_DIR/fail2ban-ui"

# ─── Step 10: systemd service ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}── systemd service ───────────────────────────────────────────${NC}"

# Determine service user
prompt SERVICE_USER "Run service as user" "root"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Fail2Ban UI
After=network.target
$(if [[ "$DB_TYPE" == "postgres" ]]; then echo "After=postgresql.service"; fi)
Wants=fail2ban.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/fail2ban-ui
EnvironmentFile=$ENV_FILE
Restart=always
RestartSec=5
User=$SERVICE_USER
Group=$SERVICE_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fail2ban-ui
systemctl restart fail2ban-ui
success "Service started: $(systemctl is-active fail2ban-ui)"

# ─── Step 11: Save installer config for update.sh ──────────────────────────
cat > "$INSTALL_CONF" <<EOF
INSTALL_DIR=$INSTALL_DIR
SERVICE_USER=$SERVICE_USER
EOF
chmod 600 "$INSTALL_CONF"

# ─── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           Installation complete!         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Service:    ${CYAN}systemctl status fail2ban-ui${NC}"
echo -e "  Logs:       ${CYAN}journalctl -u fail2ban-ui -f${NC}"
echo -e "  Env file:   ${CYAN}$ENV_FILE${NC}"
echo -e "  Update:     ${CYAN}sudo $INSTALL_DIR/update.sh${NC}"
echo ""
if [[ "$APP_BIND" == "127.0.0.1" ]]; then
    warn "Bound to 127.0.0.1 — wire it up in your reverse proxy."
    echo -e "  Example Nginx location block:"
    echo -e "  ${CYAN}location / { proxy_pass http://127.0.0.1:$APP_PORT; }${NC}"
fi
echo ""

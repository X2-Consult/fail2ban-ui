#!/bin/bash
# Fail2ban-UI Update Script
# Pulls latest code, rebuilds CSS + binary, restarts the service.
# Run as root: sudo ./update.sh  (or sudo /opt/fail2ban-ui/update.sh)

set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Root check ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Please run as root: sudo ./update.sh"

# ─── Locate install dir ──────────────────────────────────────────────────────
# Prefer the installer config, fall back to the directory of this script.
INSTALLER_CONF="/etc/fail2ban-ui/installer.conf"
if [[ -f "$INSTALLER_CONF" ]]; then
    # shellcheck source=/dev/null
    source "$INSTALLER_CONF"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    INSTALL_DIR="$SCRIPT_DIR"
    warn "Installer config not found — assuming install dir is $INSTALL_DIR"
fi

[[ -f "$INSTALL_DIR/go.mod" ]] || die "Cannot find go.mod in $INSTALL_DIR. Is INSTALL_DIR correct?"

cd "$INSTALL_DIR"

# ─── Flags ───────────────────────────────────────────────────────────────────
FORCE_CSS=0
SKIP_PULL=0
for arg in "$@"; do
    case "$arg" in
        --force-css)  FORCE_CSS=1 ;;
        --skip-pull)  SKIP_PULL=1 ;;
        --help|-h)
            echo "Usage: sudo $0 [--force-css] [--skip-pull]"
            echo "  --force-css   Rebuild Tailwind CSS even if templates/JS haven't changed"
            echo "  --skip-pull   Skip git pull (useful when testing local changes)"
            exit 0
            ;;
    esac
done

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        Fail2ban-UI  Updater              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ─── Step 1: Git pull ────────────────────────────────────────────────────────
if [[ "$SKIP_PULL" -eq 1 ]]; then
    warn "Skipping git pull (--skip-pull)."
else
    echo -e "${BOLD}── Pulling latest code ───────────────────────────────────────${NC}"
    # Capture what changed so we can decide what to rebuild.
    BEFORE_HASH="$(git rev-parse HEAD 2>/dev/null || echo 'none')"
    git pull --ff-only
    AFTER_HASH="$(git rev-parse HEAD)"

    if [[ "$BEFORE_HASH" == "$AFTER_HASH" ]]; then
        info "Already up to date ($(git log -1 --format='%h %s'))."
    else
        success "Updated $(git log --oneline "${BEFORE_HASH}..${AFTER_HASH}" | wc -l) commit(s)."
        git log --oneline "${BEFORE_HASH}..${AFTER_HASH}"
    fi
fi

# ─── Step 2: Detect what changed ─────────────────────────────────────────────
# Check if CSS-affecting files changed since the last build (or if forced).
CSS_SOURCES_CHANGED=0
if [[ "$FORCE_CSS" -eq 1 ]]; then
    CSS_SOURCES_CHANGED=1
elif [[ -f pkg/web/static/tailwind.css ]]; then
    # Compare mtime of compiled CSS vs source files
    NEWEST_SOURCE="$(find pkg/web/templates pkg/web/static/js tailwind.config.js \
        -newer pkg/web/static/tailwind.css 2>/dev/null | head -1)"
    [[ -n "$NEWEST_SOURCE" ]] && CSS_SOURCES_CHANGED=1
else
    CSS_SOURCES_CHANGED=1   # no compiled CSS yet
fi

# ─── Step 3: Rebuild Tailwind CSS ────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Tailwind CSS ──────────────────────────────────────────────${NC}"
if [[ "$CSS_SOURCES_CHANGED" -eq 1 ]]; then
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        bash "$INSTALL_DIR/build-tailwind.sh"
    else
        warn "Node.js not found — skipping Tailwind rebuild."
        warn "Install Node.js or run with --force-css after installing it."
    fi
else
    info "No CSS source changes detected — skipping Tailwind rebuild."
    info "Use --force-css to rebuild anyway."
fi

# ─── Step 4: Sync Go dependencies ────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Go dependencies ───────────────────────────────────────────${NC}"
if command -v go &>/dev/null; then
    go mod tidy
    success "Go modules up to date."
else
    # Try snap path
    export PATH="$PATH:/snap/bin"
    if command -v go &>/dev/null; then
        go mod tidy
        success "Go modules up to date."
    else
        die "Go not found. Install it with: snap install go --classic"
    fi
fi

# ─── Step 5: Build binary ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Building binary ───────────────────────────────────────────${NC}"
NEW_BINARY="$INSTALL_DIR/fail2ban-ui.new"
CGO_ENABLED=0 go build -ldflags="-s -w" -o "$NEW_BINARY" ./cmd/server/main.go

# ─── Step 6: Restart service ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Restarting service ────────────────────────────────────────${NC}"

if systemctl is-active --quiet fail2ban-ui; then
    info "Stopping fail2ban-ui..."
    systemctl stop fail2ban-ui
fi

# Swap binary atomically
mv "$NEW_BINARY" "$INSTALL_DIR/fail2ban-ui"
success "Binary updated."

systemctl daemon-reload
systemctl start fail2ban-ui

# Wait briefly and confirm it's running
sleep 2
if systemctl is-active --quiet fail2ban-ui; then
    success "Service restarted successfully."
    systemctl status fail2ban-ui --no-pager -l | head -10
else
    die "Service failed to start. Check logs: journalctl -u fail2ban-ui -n 50"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
success "Update complete. $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Logs: ${CYAN}journalctl -u fail2ban-ui -f${NC}"
echo ""

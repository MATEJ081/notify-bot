#!/bin/bash
set -euo pipefail

# Deploy script for notify-bot MCP server on home server
# Usage:
#   bash deploy.sh                    # interactive setup
#   bash deploy.sh --tailscale        # setup Tailscale + systemd
#   bash deploy.sh --systemd          # just setup systemd

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/opt/notify-bot"
SERVICE_NAME="notify-bot"

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[✓] $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

setup_user() {
    log_info "Setting up service user..."
    if ! id "_notify-bot" &>/dev/null; then
        useradd -r -s /bin/false -d /nonexistent -m _notify-bot
        log_success "User _notify-bot created"
    else
        log_info "User _notify-bot already exists"
    fi
}

setup_directories() {
    log_info "Setting up directories..."
    mkdir -p "$INSTALL_PATH"
    mkdir -p "$INSTALL_PATH/logs"
    mkdir -p "$INSTALL_PATH/state"

    chown -R _notify-bot:_notify-bot "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    chmod 700 "$INSTALL_PATH/logs" "$INSTALL_PATH/state"

    log_success "Directories ready"
}

install_files() {
    log_info "Copying files to $INSTALL_PATH..."
    cp "$SCRIPT_DIR"/{telegram_notifier.py,mcp_server.py,notify.py} "$INSTALL_PATH/"
    cp "$SCRIPT_DIR/requirements.txt" "$INSTALL_PATH/"

    # Copy .env if it exists, else .env.example
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$INSTALL_PATH/.env"
        chmod 600 "$INSTALL_PATH/.env"
        log_info ".env copied (from local)"
    elif [[ -f "$SCRIPT_DIR/.env.example" ]]; then
        cp "$SCRIPT_DIR/.env.example" "$INSTALL_PATH/.env"
        chmod 600 "$INSTALL_PATH/.env"
        log_info ".env created from .env.example (EDIT THIS!)"
    fi

    chown -R _notify-bot:_notify-bot "$INSTALL_PATH"
    log_success "Files installed"
}

setup_venv() {
    log_info "Setting up Python venv..."
    cd "$INSTALL_PATH"
    python3 -m venv venv
    chown -R _notify-bot:_notify-bot venv

    # Install dependencies
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install -r requirements.txt

    log_success "Venv ready with dependencies"
}

setup_systemd() {
    log_info "Setting up systemd service..."
    cp "$SCRIPT_DIR/notify-bot.service" "/etc/systemd/system/$SERVICE_NAME.service"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME.service"

    log_success "Systemd service registered"
}

start_service() {
    log_info "Starting $SERVICE_NAME..."
    systemctl start "$SERVICE_NAME.service"

    # Give it a moment to start
    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME.service"; then
        log_success "Service is running"
        systemctl status "$SERVICE_NAME.service" --no-pager
    else
        log_error "Service failed to start. Check logs with: journalctl -u $SERVICE_NAME"
        return 1
    fi
}

setup_tailscale() {
    log_info "Setting up Tailscale..."

    if ! command -v tailscale &>/dev/null; then
        log_error "Tailscale not installed. Install it first:"
        log_error "  curl -fsSL https://tailscale.com/install.sh | sh"
        return 1
    fi

    # Check if already authenticated
    if tailscale status &>/dev/null; then
        log_info "Tailscale already authenticated"
    else
        log_info "Tailscale not authenticated yet. Run:"
        log_info "  sudo tailscale up --authkey=<your-auth-key>"
        log_info "  (get auth key from https://login.tailscale.com/admin/settings/keys)"
    fi

    # Get Tailscale IP
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
    if [[ -n "$TAILSCALE_IP" ]]; then
        log_success "Tailscale IP: $TAILSCALE_IP"
        log_info "MCP server will be accessible at: http://$TAILSCALE_IP:5000"
    fi
}

check_config() {
    log_info "Checking configuration..."

    if [[ ! -f "$INSTALL_PATH/.env" ]]; then
        log_error ".env not found at $INSTALL_PATH/.env"
        return 1
    fi

    # Source .env (only for checking)
    set +u
    . "$INSTALL_PATH/.env"
    set -u

    if [[ -z "${BOT_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_error "BOT_TOKEN or TELEGRAM_CHAT_ID not set in .env"
        return 1
    fi

    log_success "Configuration looks good"
}

verify_service() {
    log_info "Verifying service health..."

    # Give service time to start
    sleep 2

    if curl -s http://127.0.0.1:5000/health &>/dev/null; then
        log_success "Health check passed"
    else
        log_error "Health check failed. Check logs: journalctl -u $SERVICE_NAME -f"
        return 1
    fi
}

main() {
    check_root

    MODE="${1:-interactive}"

    case "$MODE" in
        --tailscale)
            log_info "Running full setup (Tailscale + systemd)..."
            setup_user
            setup_directories
            install_files
            setup_venv
            check_config
            setup_systemd
            start_service
            setup_tailscale
            verify_service
            log_success "Deploy complete! Access via Tailscale."
            ;;
        --systemd)
            log_info "Running systemd setup only..."
            setup_user
            setup_directories
            install_files
            setup_venv
            check_config
            setup_systemd
            start_service
            verify_service
            log_success "Deploy complete! Access via localhost:5000"
            ;;
        *)
            log_info "Interactive setup"
            setup_user
            setup_directories
            install_files
            setup_venv
            check_config
            setup_systemd

            read -p "Start service now? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                start_service
                verify_service
                log_success "Deploy complete!"
            else
                log_info "Skipped. Start manually with: systemctl start $SERVICE_NAME"
            fi
            ;;
    esac
}

main "$@"

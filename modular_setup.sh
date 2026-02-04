#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ========================
# Globals / Flags
# ========================
LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"
DRY_RUN=false
NON_INTERACTIVE=false

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
  esac
done

rotate_logs() {
  [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
  : > "$LOG_FILE"
}

rotate_logs

# ========================
# Load libs
# ========================
source lib/ui.sh
source lib/system.sh
source lib/env.sh
source lib/host.sh
source lib/stack.sh

log_info "🚀 n8n Stage 1 Lean Setup Starting"

# ========================
# System detection
# ========================
DISTRO=$(detect_distro)
ARCH=$(detect_arch)
log_info "Detected distro: $DISTRO"
log_info "Detected arch: $ARCH"

# ========================
# Dependencies
# ========================
log_info "🔧 Ensuring dependencies..."
for dep in curl awk sed grep getent openssl ss; do install_pkg "$dep"; done

install_docker
install_compose_plugin

# ========================
# Docker permissions
# ========================
ensure_docker_group

# ========================
# Detect latest n8n
# ========================
log_info "🔎 Detecting latest stable n8n version..."
N8N_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100 \
  | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
  | sed 's/"name":"//;s/"//' \
  | sort -Vr | head -n1)

[ -z "$N8N_VERSION" ] && { log_error "Could not detect n8n version"; exit 1; }
log_info "Latest stable n8n: $N8N_VERSION"

# ========================
# UI Header
# ========================
ui_header "🚀 n8n Deployment Setup" "Configure your installation"

# ========================
# User input
# ========================
prompt DOMAIN "Enter domain / IP / hostname" "n8n.local"
prompt PORT "Enter n8n internal port" "5678"
SETUP_LOCALHOST=false

if command -v gum >/dev/null 2>&1; then
  gum confirm "Enable localhost.n8n alias?" && SETUP_LOCALHOST=true
else
  read -rp "Enable localhost.n8n alias? [Y/n]: " r
  [[ "${r:-Y}" =~ ^[Yy]$ ]] && SETUP_LOCALHOST=true
fi

check_port "$PORT" || log_warn "Port may already be in use"
check_dns "$DOMAIN" || log_warn "DNS not resolving for $DOMAIN (OK for local)"

# Always ask about /etc/hosts
if command -v gum >/dev/null 2>&1; then
  gum confirm "Add $DOMAIN to /etc/hosts?" && add_hosts_entry "$DOMAIN"
else
  read -rp "Add $DOMAIN to /etc/hosts? [Y/n]: " r
  [[ "${r:-Y}" =~ ^[Yy]$ ]] && add_hosts_entry "$DOMAIN"
fi

# ========================
# Secrets + env
# ========================
load_or_create_secret
write_env_file

# ========================
# Generate configs
# ========================
log_info "Generating docker-compose.yml and Caddyfile..."

sed -e "s|{{N8N_VERSION}}|$N8N_VERSION|g" \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{ENCRYPTION_KEY}}|$ENCRYPTION_KEY|g" \
    -e "s|{{UID}}|$(id -u)|g" \
    -e "s|{{GID}}|$(id -g)|g" \
    docker-compose.yml.template > docker-compose.yml

if [ "$SETUP_LOCALHOST" = "true" ]; then
cat > Caddyfile <<EOF
$DOMAIN {
    reverse_proxy n8n:$PORT
}

localhost.n8n {
    tls internal
    reverse_proxy n8n:$PORT
}
EOF
else
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{PORT}}|$PORT|g" \
    Caddyfile.template > Caddyfile
fi

# ========================
# Data dirs
# ========================
log_info "Ensuring data directories..."
mkdir -p data/n8n data/caddy data/caddy-config logs
sudo chown -R "$(id -u):$(id -g)" data logs

# ========================
# Start stack
# ========================
start_stack

# ========================
# Health checks
# ========================
wait_for_container "n8n" 90
wait_for_container "caddy" 30

log_info "🎉 All services are running!"
log_info "Access: https://$DOMAIN"
[ "$SETUP_LOCALHOST" = "true" ] && log_info "Local: https://localhost.n8n"

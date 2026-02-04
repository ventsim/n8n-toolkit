#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"

[ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
: > "$LOG_FILE"

source lib/ui.sh
source lib/system.sh
source lib/env.sh
source lib/host.sh
source lib/stack.sh

log_info "🚀 n8n Stage 1 Lean Setup Starting"

ui_license

DISTRO=$(detect_distro)
ARCH=$(detect_arch)
log_info "Detected distro: $DISTRO"
log_info "Detected arch: $ARCH"

log_info "🔧 Ensuring dependencies..."
ui_run "Installing system packages" bash -c 'for dep in curl awk sed grep getent openssl ss; do install_pkg "$dep"; done'

ui_run "Installing Docker" install_docker
ui_run "Installing Docker Compose" install_compose_plugin

ui_run "Detecting latest n8n version" bash -c '
N8N_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100 \
  | grep -oE '"'"'"name":"[0-9]+\.[0-9]+\.[0-9]+"'"'"' \
  | sed '"'"'s/"name":"//;s/"//'"'"' \
  | sort -Vr | head -n1)
echo "$N8N_VERSION"
'
ui_header "🚀 n8n Deployment Setup" "Configure your installation"

prompt DOMAIN "Enter domain / IP / hostname" "n8n.local"
prompt PORT "Enter n8n internal port" "5678"

SETUP_LOCALHOST=false
command -v gum >/dev/null 2>&1 && gum confirm "Enable localhost.n8n alias?" && SETUP_LOCALHOST=true

check_port "$PORT" || log_warn "Port may already be in use"
check_dns "$DOMAIN" || log_warn "DNS not resolving (OK for local)"

command -v gum >/dev/null 2>&1 && gum confirm "Add $DOMAIN to /etc/hosts?" && add_hosts_entry "$DOMAIN"

load_or_create_secret
write_env_file

log_info "Generating configs..."
sed -e "s|{{N8N_VERSION}}|$N8N_VERSION|g" \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{ENCRYPTION_KEY}}|$ENCRYPTION_KEY|g" \
    -e "s|{{UID}}|$(id -u)|g" \
    -e "s|{{GID}}|$(id -g)|g" docker-compose.yml.template > docker-compose.yml

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
sed -e "s|{{DOMAIN}}|$DOMAIN|g" -e "s|{{PORT}}|$PORT|g" Caddyfile.template > Caddyfile
fi

log_info "Ensuring data directories..."
mkdir -p data/n8n data/caddy data/caddy-config logs
sudo chown -R "$(id -u):$(id -g)" data logs

ui_run "Starting n8n stack" start_stack
wait_for_container "n8n" 90
wait_for_container "caddy" 30

ui_final_screen
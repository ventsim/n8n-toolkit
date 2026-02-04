#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ========================
# Globals / Defaults
# ========================
LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"

INTERACTIVE=false
CONFIG_FILE=""

# Defaults (silent-first)
DOMAIN="n8n.local"
PORT="5678"
SETUP_LOCALHOST=true
N8N_VERSION="latest"

# ========================
# Parse Args
# ========================
for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=true ;;
    --domain=*) DOMAIN="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --setup-localhost=*) SETUP_LOCALHOST="${arg#*=}" ;;
    --n8n-version=*) N8N_VERSION="${arg#*=}" ;;
    --config=*) CONFIG_FILE="${arg#*=}" ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

# ========================
# Rotate logs
# ========================
[ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
: > "$LOG_FILE"

# ========================
# Load libs
# ========================
source lib/ui.sh
source lib/system.sh
source lib/env.sh
source lib/host.sh
source lib/stack.sh

log_info "🚀 n8n Development Stack Setup Starting"

# ========================
# Load from config file (if provided)
# ========================
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  log_info "Loading config from $CONFIG_FILE"
  source "$CONFIG_FILE"
fi

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
if [ "$N8N_VERSION" = "latest" ]; then
  log_info "🔎 Detecting latest stable n8n version..."
  N8N_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100 \
    | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
    | sed 's/"name":"//;s/"//' \
    | sort -Vr | head -n1)

  [ -z "$N8N_VERSION" ] && { log_error "Could not detect n8n version"; exit 1; }
fi

log_info "Using n8n version: $N8N_VERSION"

# ========================
# Interactive Template Builder
# ========================
if $INTERACTIVE; then
  ui_header "🚀 n8n Deployment Setup" "Template Builder Mode"

  prompt DOMAIN "Enter domain / IP / hostname" "$DOMAIN"
  prompt PORT "Enter n8n internal port" "$PORT"

  if command -v gum >/dev/null 2>&1; then
    gum confirm "Enable localhost.n8n alias?" && SETUP_LOCALHOST=true || SETUP_LOCALHOST=false
  else
    read -rp "Enable localhost.n8n alias? [Y/n]: " r
    [[ "${r:-Y}" =~ ^[Yy]$ ]] && SETUP_LOCALHOST=true || SETUP_LOCALHOST=false
  fi
fi

# ========================
# Validation
# ========================
check_port "$PORT" || log_warn "Port may already be in use"
check_dns "$DOMAIN" || log_warn "DNS not resolving for $DOMAIN (OK for local)"

# Always ask about /etc/hosts in interactive mode
if $INTERACTIVE; then
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Add $DOMAIN to /etc/hosts?" && add_hosts_entry "$DOMAIN"
  else
    read -rp "Add $DOMAIN to /etc/hosts? [Y/n]: " r
    [[ "${r:-Y}" =~ ^[Yy]$ ]] && add_hosts_entry "$DOMAIN"
  fi
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

# ========================
# Template Output (if interactive)
# ========================
if $INTERACTIVE; then
  log_info "Writing deploy.env template..."

  cat > deploy.env <<EOF
DOMAIN="$DOMAIN"
PORT="$PORT"
SETUP_LOCALHOST="$SETUP_LOCALHOST"
N8N_VERSION="$N8N_VERSION"
EOF

  echo ""
  log_info "Reusable silent install command:"
  echo "------------------------------------------------"
  echo "./setup.sh \\"
  echo "  --domain=\"$DOMAIN\" \\"
  echo "  --port=\"$PORT\" \\"
  echo "  --setup-localhost=\"$SETUP_LOCALHOST\" \\"
  echo "  --n8n-version=\"$N8N_VERSION\""
  echo "------------------------------------------------"
  echo ""
  log_info "Or run again with:"
  echo "  ./setup.sh --config deploy.env"
fi

# ========================
# Final Page (Modular)
# ========================
render_final_page

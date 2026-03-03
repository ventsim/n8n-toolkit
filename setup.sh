#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"
STATE_FILE=".install-state.env"

INTERACTIVE=false
DOMAIN="n8n.local"
PORT="5678"
SETUP_LOCALHOST=true
N8N_VERSION="latest"

# ========================
# Detect previous run
# ========================
if [ -f "$STATE_FILE" ]; then
  echo "⚠️ Previous installation detected."
  echo "Run cleanup.sh before reinstalling."
  exit 1
fi

# ========================
# Parse args
# ========================
for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=true ;;
    --domain=*) DOMAIN="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --setup-localhost=*) SETUP_LOCALHOST="${arg#*=}" ;;
    --version=*) N8N_VERSION="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ========================
# Rotate logs
# ========================
[ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
: > "$LOG_FILE"

# ========================
# Init state
# ========================
: > "$STATE_FILE"
track() { echo "$1" >> "$STATE_FILE"; }

source lib/ui.sh
source lib/system.sh
source lib/env.sh
source lib/host.sh
source lib/stack.sh
source lib/deps.sh

log_info "🚀 n8n Stage 1 Setup Starting"

DISTRO=$(detect_distro)
ARCH=$(detect_arch)
log_info "Detected distro: $DISTRO"
log_info "Detected arch: $ARCH"

# ========================
# Dependencies
# ========================
INSTALLED_PKGS=()
for dep in curl awk sed grep getent openssl ss; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    install_pkg "$dep"
    INSTALLED_PKGS+=("$dep")
  fi
done
[ ${#INSTALLED_PKGS[@]} -gt 0 ] && track "INSTALLED_PKGS=\"${INSTALLED_PKGS[*]}\""

if ! command -v docker >/dev/null 2>&1; then
  install_docker
  track "INSTALLED_DOCKER=true"
fi

if ! command -v gum >/dev/null 2>&1; then
  install_gum

  track "INSTALLED_GUM=true"
fi


# ========================
# Docker group
# ========================
ensure_docker_group

# ========================
# Detect n8n version
# ========================
if [ "$N8N_VERSION" = "latest" ]; then
  N8N_VERSION=$(detect_latest_n8n)
fi

log_info "Using n8n version: $N8N_VERSION"

# ========================
# Interactive
# ========================
if $INTERACTIVE; then
  ui_header "n8n Stage 1 Setup" "Interactive Mode"
  prompt DOMAIN "Domain" "$DOMAIN"
  prompt PORT "Port" "$PORT"
fi

# ========================
# Validation
# ========================
check_port "$PORT" || true
check_dns "$DOMAIN" || true

# ========================
# Secrets
# ========================
load_or_create_secret
write_env_file

# ========================
# Generate config
# ========================
generate_compose "$N8N_VERSION" "$PORT" "$DOMAIN" "$ENCRYPTION_KEY"
generate_caddy "$PORT" "$DOMAIN" "$SETUP_LOCALHOST"

# ========================
# Data dirs
# ========================
mkdir -p data logs secrets
track "CREATED_DIRS=\"data logs secrets\""

# ========================
# Start
# ========================
start_stack
wait_for_container "n8n" 60
wait_for_container "caddy" 30

render_final_page
track "INSTALL_COMPLETED_AT=\"$(date -Is)\""
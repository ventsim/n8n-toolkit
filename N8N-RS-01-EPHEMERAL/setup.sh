#!/usr/bin/env bash
set -Eeuo pipefail

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

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

run() {
  if $DRY_RUN; then
    log "[DRY-RUN] $*"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

rotate_logs
log "🚀 n8n Stage 1 Lean Setup Starting"

# ========================
# Distro detection
# ========================
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)
log "Detected distro: $DISTRO"

# ========================
# Install deps
# ========================
install_pkg() {
  local pkg="$1"
  command -v "$pkg" >/dev/null 2>&1 && return 0

  log "Installing $pkg..."
  case "$DISTRO" in
    ubuntu|debian)
      run "sudo apt-get update -y"
      run "sudo apt-get install -y $pkg"
      ;;
    rocky|almalinux|centos|rhel)
      run "sudo dnf install -y $pkg"
      ;;
    arch)
      run "sudo pacman -Sy --noconfirm $pkg"
      ;;
    *)
      log "❌ Unsupported distro for auto-install: $DISTRO"
      exit 1
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed"
    return
  fi

  log "Installing Docker..."
  case "$DISTRO" in
    ubuntu|debian)
      run "curl -fsSL https://get.docker.com | sudo sh"
      ;;
    rocky|almalinux|centos|rhel)
      run "curl -fsSL https://get.docker.com | sudo sh"
      ;;
    arch)
      run "sudo pacman -Sy --noconfirm docker"
      run "sudo systemctl enable --now docker"
      ;;
    *)
      log "❌ Docker install unsupported on $DISTRO"
      exit 1
      ;;
  esac
}

# ========================
# Install dependencies
# ========================
log "🔧 Ensuring dependencies..."

for dep in curl awk sed grep getent openssl; do
  install_pkg "$dep"
done

install_docker
run "sudo systemctl enable --now docker || true"

# ========================
# Helpers
# ========================
prompt() {
  local var="$1" text="$2" def="$3"
  if $NON_INTERACTIVE; then
    eval "$var=\"$def\""
    log "Using default for $var=$def"
  else
    while true; do
      read -rp "$text [$def]: " val
      val="${val:-$def}"
      [ -n "$val" ] && break
    done
    eval "$var=\"$val\""
  fi
}

generate_key() { openssl rand -hex 32; }

check_port() {
  local p="$1"
  if ! [[ "$p" =~ ^[0-9]+$ ]] || [ "$p" -lt 1024 ] || [ "$p" -gt 65535 ]; then
    log "⚠️  Port invalid. Using default 5678."
    PORT=5678
  fi
}

check_dns() {
  local host="$1"
  log "Checking DNS for $host..."
  local ip
  ip=$(getent hosts "$host" | awk '{print $1}' || true)
  if [ -z "$ip" ]; then
    echo "⚠️  DNS for $host not resolving yet."
    echo "➡ Public HTTPS will work once DNS points here."
    return 1
  fi
  log "DNS OK: $host resolves to $ip"
}

# ========================
# Detect latest n8n
# ========================
log "🔎 Detecting latest stable n8n version..."
N8N_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100 \
  | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
  | sed 's/"name":"//;s/"//' \
  | sort -Vr | head -n1)

[ -z "$N8N_VERSION" ] && { log "❌ Could not detect n8n version"; exit 1; }
log "Latest stable n8n: $N8N_VERSION"

# ========================
# User input
# ========================
prompt DOMAIN "Enter domain / IP / local hostname" "n8n.local"
prompt PORT "Enter n8n internal port" "5678"
check_port "$PORT"

check_dns "$DOMAIN" || true

# ========================
# Encryption key
# ========================
mkdir -p secrets
if [ ! -f secrets/encryption_key.txt ]; then
  ENCRYPTION_KEY=$(generate_key)
  echo "$ENCRYPTION_KEY" > secrets/encryption_key.txt
  chmod 600 secrets/encryption_key.txt
  log "🔐 Encryption key generated and saved."
else
  ENCRYPTION_KEY=$(cat secrets/encryption_key.txt)
  log "Using existing encryption key."
fi

# ========================
# Templates
# ========================
[ -f docker-compose.yml.template ] || { log "❌ docker-compose.yml.template missing"; exit 1; }
[ -f Caddyfile.template ] || { log "❌ Caddyfile.template missing"; exit 1; }

TMP_DC=$(mktemp)
TMP_CADDY=$(mktemp)

sed -e "s|{{N8N_VERSION}}|$N8N_VERSION|g" \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{ENCRYPTION_KEY}}|$ENCRYPTION_KEY|g" \
    docker-compose.yml.template > "$TMP_DC"

sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{PORT}}|$PORT|g" \
    Caddyfile.template > "$TMP_CADDY"

run "mv $TMP_DC docker-compose.yml"
run "mv $TMP_CADDY Caddyfile"

log "📄 Files generated."

# ========================
# Final
# ========================
echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  docker compose up -d"
echo ""
echo "Access n8n at:"
echo "  https://$DOMAIN"
echo ""
echo "Keep secrets/encryption_key.txt safe!"

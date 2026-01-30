#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"
DRY_RUN=false
NON_INTERACTIVE=false
SETUP_FAILED=false

# Cleanup function
cleanup() {
  rm -f "$TMP_DC" "$TMP_CADDY" 2>/dev/null || true
}

# Error handling
trap 'SETUP_FAILED=true; setup_cleanup' ERR
trap cleanup EXIT INT TERM

setup_cleanup() {
  if $SETUP_FAILED; then
    log "❌ Setup failed. Performing cleanup..."
    run "docker compose down --volumes --remove-orphans 2>/dev/null || true"
  fi
  cleanup
}

trap setup_cleanup ERR

VERSION=""
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    --version=*) VERSION="${arg#*=}" ;;
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
  if [ -f /etc/os-release ]; then . /etc/os-release; echo "$ID"; else echo "unknown"; fi
}
DISTRO=$(detect_distro)
log "Detected distro: $DISTRO"

# ========================
# Package install helpers
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
      log "❌ Unsupported distro: $DISTRO"
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
  run "curl -fsSL https://get.docker.com | sudo sh"
}

install_compose_plugin() {
  # Check for docker compose V2 (plugin)
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose plugin already installed"
    return
  fi
  
  # Check for docker-compose V1 (standalone)
  if command -v docker-compose >/dev/null 2>&1; then
    log "docker-compose V1 detected - installing V2 plugin..."
    # Optionally remove V1 and install V2
  fi
  log "Installing Docker Compose plugin..."
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) log "❌ Unsupported arch: $ARCH"; exit 1 ;;
  esac

  local DEST="/usr/local/lib/docker/cli-plugins"
  run "sudo mkdir -p $DEST"
  local URL
  URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep browser_download_url \
    | grep "linux-$ARCH" \
    | cut -d '"' -f 4)

  [ -z "$URL" ] && { log "❌ Failed to detect Compose plugin URL"; exit 1; }

  run "sudo curl -L $URL -o $DEST/docker-compose"
  run "sudo chmod +x $DEST/docker-compose"
}

detect_n8n_version_official() {
    # Try n8n's update endpoint
    local version
    version=$(curl -s "https://static.n8n.io/releases/versions.json" \
        | grep -o '"latest":"[0-9]\+\.[0-9]\+\.[0-9]\+"' \
        | cut -d'"' -f4 2>/dev/null)
    
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    
    # Fallback to GitHub API with better error handling
    version=$(curl -s \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/n8n-io/n8n/releases/latest" \
        2>/dev/null | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    
    echo "$version"
}
# ========================
# Ensure dependencies
# ========================
log "🔧 Ensuring dependencies..."
for dep in curl awk sed grep getent openssl; do install_pkg "$dep"; done
install_docker
run "sudo systemctl enable --now docker || true"
install_compose_plugin

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

generate_key() {
  # Generate 32 random bytes, base64 encode = ~43 characters
  openssl rand -base64 32 | tr -d '\n' | head -c 32
}

check_port() {
  local port="$1"
  if ss -tuln | grep -q ":$port "; then
    log "❌ Port $port is already in use"
    if $NON_INTERACTIVE; then
      exit 1
    else
      while true; do
        read -rp "Choose another port (1024-65535): " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
          PORT="$new_port"
          break
        fi
      done
    fi
  fi
}


check_dns() {
  local host="$1"
  log "Checking DNS for $host..."
  local ip
  ip=$(getent hosts "$host" | awk '{print $1}' || true)
  if [ -z "$ip" ]; then
    log "⚠️  DNS for $host not resolving yet (OK for local use)"
    return 1
  fi
  log "DNS OK: $host resolves to $ip"
}
# ========================
# Add current user to docker group if not already added
# ========================
if ! groups "$USER" | grep -q '\bdocker\b'; then
  log "User $USER is not in docker group"
  log "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"

  echo ""
  echo "⚠️  You have been added to the docker group."
  echo "➡ You must log out and back in (or run: newgrp docker)"
  echo "➡ Then re-run this script."
  exit 0
fi
# ========================
# Detect latest n8n
# ========================
log "🔎 Detecting latest stable n8n version..."
N8N_VERSION=$(detect_n8n_version_official)

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
  log "🔐 Encryption key generated and saved"
else
  ENCRYPTION_KEY=$(cat secrets/encryption_key.txt)
  log "Using existing encryption key"
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
# ========================
# Start stack
# ========================
log "▶ Starting n8n stack..."
run "docker compose up -d"

# ========================
# Health check
# ========================
log "⏳ Waiting for n8n to become healthy..."
for i in {1..60}; do
  # Check the health endpoint directly
  if curl -f -s http://localhost:$PORT/healthz >/dev/null 2>&1; then
    log "✅ n8n health check passed"
    break
  fi
  if [ $i -eq 30 ]; then
    log "⚠️  n8n starting slowly, continuing to wait..."
  fi
  sleep 2
done

# Also check Caddy
for i in {1..30}; do
  if curl -k -f -s https://$DOMAIN/healthz >/dev/null 2>&1; then
    log "✅ Caddy proxy working"
    break
  fi
  sleep 2
done

# ========================
# Final
# ========================
echo ""
echo "✅ Setup complete!"
echo ""
echo "Access n8n at:"
echo "  https://$DOMAIN"
echo ""
echo "Check logs:"
echo "  docker compose logs -f n8n caddy"
echo ""
echo "Keep secrets/encryption_key.txt safe!"

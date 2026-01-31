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
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose plugin already installed"
    return
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
# Ensure docker group access
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
  log "🔐 Encryption key generated and saved"
else
  ENCRYPTION_KEY=$(cat secrets/encryption_key.txt)
  log "Using existing encryption key"
fi

# ========================
# Generate .env
# ========================
cat > .env <<EOF
DOMAIN=$DOMAIN
PORT=$PORT
N8N_VERSION=$N8N_VERSION
ENCRYPTION_KEY=$ENCRYPTION_KEY
UID=$(id -u)
GID=$(id -g)
EOF

log "📄 .env file written"

# ========================
# Templates
# ========================
[ -f docker-compose.yml.template ] || { log "❌ docker-compose.yml.template missing"; exit 1; }
[ -f Caddyfile.template ] || { log "❌ Caddyfile.template missing"; exit 1; }

run "cp docker-compose.yml.template docker-compose.yml"
run "cp Caddyfile.template Caddyfile"

# ========================
# Ensure data directories & permissions
# ========================
log "📁 Ensuring persistent data directories..."

mkdir -p data/n8n data/caddy data/caddy-config logs

log "🔐 Fixing ownership on data directories..."
run "sudo chown -R $(id -u):$(id -g) data logs"

log "🧪 Verifying write access..."
touch data/n8n/.perm_test && rm data/n8n/.perm_test

log "✅ Data directories ready"

# ========================
# Start stack
# ========================
log "▶ Starting stack..."
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
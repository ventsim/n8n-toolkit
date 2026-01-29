#!/usr/bin/env bash
set -Eeuo pipefail

# ========================
# Config
# ========================
LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"
DRY_RUN=false
NON_INTERACTIVE=false

# ========================
# Args
# ========================
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
  esac
done

# ========================
# Logging + rotation
# ========================
rotate_logs() {
  [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
  : > "$LOG_FILE"
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

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
# Dependency checks
# ========================
check_dep() {
  command -v "$1" >/dev/null 2>&1 || { log "❌ Missing dependency: $1"; exit 1; }
}

log "🔎 Checking dependencies..."
for d in docker curl awk sed grep getent openssl; do check_dep "$d"; done
run "docker info >/dev/null"

# ========================
# Helpers
# ========================
prompt() {
  local var="$1" text="$2" def="$3"
  if $NON_INTERACTIVE; then
    eval "$var=\"$def\""
    log "Using default for $var=$def"
  else
    read -rp "$text [$def]: " val
    eval "$var=\"${val:-$def}\""
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
    echo "➡ If you want public HTTPS later, point DNS A/AAAA to this server."
    return 1
  fi
  log "DNS OK: $host resolves to $ip"
  return 0
}

# ========================
# Detect latest stable n8n from Docker Hub
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
prompt DOMAIN "Enter domain (or IP / local hostname)" "n8n.local"
prompt PORT "Enter n8n internal port" "5678"
check_port "$PORT"

# ========================
# DNS readiness (non-fatal)
# ========================
check_dns "$DOMAIN" || true

# ========================
# Generate encryption key
# ========================
mkdir -p secrets
if [ ! -f secrets/encryption_key.txt ]; then
  ENCRYPTION_KEY=$(generate_key)
  echo "$ENCRYPTION_KEY" > secrets/encryption_key.txt
  chmod 600 secrets/encryption_key.txt
  log "🔐 Encryption key generated!"
  echo ""
  echo "⚠️  IMPORTANT:"
  echo "   This encryption key is REQUIRED to migrate, restore backups,"
  echo "   and decrypt credentials."
  echo "   LOSS OF THIS KEY = DATA LOSS."
  echo ""
  echo "   Key saved in: secrets/encryption_key.txt"
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

log "📄 Files generated: docker-compose.yml, Caddyfile"

# ========================
# Final output
# ========================
echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Start services:"
echo "      docker compose up -d"
echo ""
echo "   2. Check logs:"
echo "      docker compose logs -f n8n caddy"
echo ""
echo "   3. Access n8n at:"
echo "      https://$DOMAIN"
echo ""
echo "🔒 Remember:"
echo "   - Keep secrets/encryption_key.txt secure!"
echo "   - Loss of encryption key = lost credentials."

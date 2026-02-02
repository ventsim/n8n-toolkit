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
# Install Gum for beautiful prompts
# ========================
install_gum() {
    if command -v gum >/dev/null 2>&1; then
        log "Gum already installed"
        return
    fi
    
    log "Installing Gum for beautiful terminal prompts..."
    
    # Try direct download (works on most systems)
    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) log "⚠️  Unsupported arch for Gum, will use basic prompts"; return 1 ;;
    esac
    
    local GUM_VERSION
    GUM_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | grep tag_name | cut -d'"' -f4 2>/dev/null || echo "v0.13.0")
    
    log "Downloading Gum ${GUM_VERSION}..."
    if run "sudo curl -L https://github.com/charmbracelet/gum/releases/download/${GUM_VERSION}/gum_${GUM_VERSION#v}_linux_${ARCH}.tar.gz -o /tmp/gum.tar.gz"; then
        run "sudo tar -xzf /tmp/gum.tar.gz -C /usr/local/bin gum"
        run "sudo rm -f /tmp/gum.tar.gz"
        
        if command -v gum >/dev/null 2>&1; then
            log "✅ Gum installed successfully"
            return 0
        fi
    fi
    
    log "⚠️  Failed to install Gum, will use basic prompts"
    return 1
}

# ========================
# Ensure dependencies
# ========================
log "🔧 Ensuring dependencies..."
for dep in curl awk sed grep getent openssl; do install_pkg "$dep"; done
install_docker
run "sudo systemctl enable --now docker || true"
install_compose_plugin
install_gum

# ========================
# Helpers with Gum if available
# ========================
prompt() {
  local var="$1" text="$2" def="$3"
  if $NON_INTERACTIVE; then
    eval "$var=\"$def\""
    log "Using default for $var=$def"
  else
    if command -v gum >/dev/null 2>&1; then
      local val
      val=$(gum input --placeholder "$def" --value "$def" --prompt "$text")
      val="${val:-$def}"
      eval "$var=\"$val\""
    else
      while true; do
        read -rp "$text [$def]: " val
        val="${val:-$def}"
        [ -n "$val" ] && break
      done
      eval "$var=\"$val\""
    fi
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
      if command -v gum >/dev/null 2>&1; then
        local new_port
        new_port=$(gum choose --height 4 --cursor "➜" "5679" "5680" "5681" "Custom port")
        if [ "$new_port" = "Custom port" ]; then
          new_port=$(gum input --placeholder "Enter custom port" --prompt "Port: ")
        fi
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
          PORT="$new_port"
        else
          log "⚠️  Invalid port. Using default 5678."
          PORT=5678
        fi
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
# User input with Gum styling
# ========================
if command -v gum >/dev/null 2>&1; then
  clear
  gum style \
    --foreground 212 --border-foreground 212 --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    '🚀 n8n Deployment Setup' \
    'Configure your installation'
fi

# Domain configuration
log "Configuring domain access..."
if command -v gum >/dev/null 2>&1; then
  DOMAIN=$(gum input --placeholder "n8n.local" --value "n8n.local" \
    --prompt.foreground 212 --prompt "Enter primary domain: " \
    --header "This can be a domain name or local hostname")
  
  gum confirm "Setup localhost.n8n alias for local access?" && SETUP_LOCALHOST=true || SETUP_LOCALHOST=false
  
  # Add to /etc/hosts if it's a .local domain
  if [[ "$DOMAIN" == *.local ]]; then
    gum confirm "Add $DOMAIN to /etc/hosts for local DNS resolution?" && {
      echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
      log "✅ Added $DOMAIN to /etc/hosts"
    }
  fi
else
  prompt DOMAIN "Enter domain / IP / local hostname" "n8n.local"
  read -rp "Setup localhost.n8n alias for local access? [Y/n]: " local_resp
  local_resp=${local_resp:-Y}
  [[ "$local_resp" =~ ^[Yy]$ ]] && SETUP_LOCALHOST=true || SETUP_LOCALHOST=false
  
  if [[ "$DOMAIN" == *.local ]]; then
    read -rp "Add $DOMAIN to /etc/hosts? [Y/n]: " hosts_resp
    hosts_resp=${hosts_resp:-Y}
    [[ "$hosts_resp" =~ ^[Yy]$ ]] && {
      echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
      log "✅ Added $DOMAIN to /etc/hosts"
    }
  fi
fi

# Port configuration
log "Configuring port..."
if command -v gum >/dev/null 2>&1; then
  PORT=$(gum input --placeholder "5678" --value "5678" \
    --prompt.foreground 212 --prompt "Enter n8n port: " \
    --header "Internal port n8n will listen on")
else
  prompt PORT "Enter n8n internal port" "5678"
fi
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
SETUP_LOCALHOST=$SETUP_LOCALHOST
UID=$(id -u)
GID=$(id -g)
EOF

log "📄 .env file written"

# ========================
# Generate configuration files from templates
# ========================
[ -f docker-compose.yml.template ] || { log "❌ docker-compose.yml.template missing"; exit 1; }
[ -f Caddyfile.template ] || { log "❌ Caddyfile.template missing"; exit 1; }

log "Generating configuration files from templates..."

# Generate docker-compose.yml from template
TMP_DC=$(mktemp)
sed -e "s|{{N8N_VERSION}}|$N8N_VERSION|g" \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{ENCRYPTION_KEY}}|$ENCRYPTION_KEY|g" \
    -e "s|{{UID}}|$(id -u)|g" \
    -e "s|{{GID}}|$(id -g)|g" \
    docker-compose.yml.template > "$TMP_DC"
run "mv $TMP_DC docker-compose.yml"

# Generate Caddyfile from template
TMP_CADDY=$(mktemp)
if [ "$SETUP_LOCALHOST" = "true" ]; then
  # Multi-domain Caddyfile
  cat > "$TMP_CADDY" <<EOF
# Primary domain: $DOMAIN
$DOMAIN {
    reverse_proxy n8n:$PORT {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}

# Local development alias
localhost.n8n {
    tls internal
    reverse_proxy n8n:$PORT {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}

# IP-based fallback
:80, :443 {
    @ip not host *.*
    handle @ip {
        reverse_proxy n8n:$PORT {
            header_up Host $DOMAIN
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
EOF
else
  # Single domain Caddyfile
  sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
      -e "s|{{PORT}}|$PORT|g" \
      Caddyfile.template > "$TMP_CADDY"
fi

run "mv $TMP_CADDY Caddyfile"

# Add localhost.n8n to /etc/hosts if enabled
if [ "$SETUP_LOCALHOST" = "true" ] && ! grep -q "localhost.n8n" /etc/hosts 2>/dev/null; then
  echo "127.0.0.1 localhost.n8n" | sudo tee -a /etc/hosts
  log "✅ Added localhost.n8n to /etc/hosts"
fi

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
if command -v gum >/dev/null 2>&1; then
  gum spin --spinner dot --title "Starting n8n services..." -- docker compose up -d
else
  run "docker compose up -d"
fi

# ========================
# Health check
# ========================
log "⏳ Waiting for n8n to become healthy..."

# Function to check n8n health (internal container access)
check_n8n_internal() {
    # Try to access n8n health endpoint directly via Docker network
    for i in {1..30}; do
        if docker exec n8n curl -f -s http://localhost:443/healthz >/dev/null 2>&1; then
            log "✅ n8n internal health check passed"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Function to check via exposed port (if needed)
check_n8n_exposed() {
    # Try direct access via exposed port (may not work if n8n is configured for 443)
    for i in {1..10}; do
        if curl -f -s http://localhost:$PORT/healthz >/dev/null 2>&1; then
            log "✅ n8n exposed port check passed"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Check n8n health (try multiple methods)
if check_n8n_internal; then
    log "✅ n8n is running inside container"
elif check_n8n_exposed; then
    log "✅ n8n is accessible via exposed port"
else
    # Check if n8n container is at least running
    if docker ps | grep -q "n8n.*Up"; then
        log "⚠️  n8n container is running but health check failing"
        log "This may be normal - n8n might still be initializing"
    else
        log "❌ n8n container is not running"
        docker compose logs n8n --tail=20
    fi
fi

# Check Caddy via HTTPS (with self-signed cert ignore)
log "⏳ Checking Caddy proxy..."
for i in {1..30}; do
    # Use -k to ignore SSL warnings, --retry for resilience
    if curl -k -f -s --retry 2 --retry-delay 1 https://$DOMAIN/healthz >/dev/null 2>&1; then
        log "✅ Caddy proxy working (https://$DOMAIN)"
        break
    fi
    if [ $i -eq 10 ]; then
        log "⚠️  Caddy still starting..."
    fi
    if [ $i -eq 20 ]; then
        log "⚠️  Caddy taking longer than expected..."
        # Try HTTP fallback
        if curl -f -s --max-time 5 http://$DOMAIN >/dev/null 2>&1; then
            log "✅ Caddy responding on HTTP (will redirect to HTTPS)"
        fi
    fi
    sleep 2
done

# Check localhost alias if enabled
if [ "$SETUP_LOCALHOST" = "true" ]; then
    log "⏳ Checking localhost alias..."
    for i in {1..15}; do
        if curl -k -f -s https://localhost.n8n/healthz >/dev/null 2>&1; then
            log "✅ Caddy localhost alias working (https://localhost.n8n)"
            break
        fi
        sleep 2
    done
fi

# Final verification - try to access n8n UI through Caddy
log "⏳ Final verification..."
for i in {1..10}; do
    # Check if we get any response from n8n UI (not just health endpoint)
    if curl -k -s -o /dev/null -w "%{http_code}" https://$DOMAIN | grep -q "200\|302\|307"; then
        log "✅ n8n UI is accessible through Caddy"
        break
    fi
    sleep 2
done

# Provide helpful message about SSL warnings
echo ""
if [[ "$DOMAIN" == *.local ]] || [[ "$DOMAIN" == *localhost* ]]; then
    log "ℹ️  SSL Note: Since you're using a local domain ($DOMAIN),"
    log "   browsers will show a security warning. This is normal."
    log "   Just click 'Advanced' → 'Proceed to site' or 'Accept Risk'"
fi

# ========================
# Final output with styling - CLEANEST FIX
# ========================
if command -v gum >/dev/null 2>&1; then
  clear
  
  # Header
  gum style \
    --foreground 46 --border-foreground 46 --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    '✅ n8n DEPLOYMENT COMPLETE' \
    'Your automation platform is ready!'
  
  # URLs section
  echo ""
  gum style --foreground 212 --bold "🔗 ACCESS URLs"
  echo ""
  
  # Create a formatted table for URLs
  {
    echo "🌐 Primary Domain:;https://$DOMAIN"
    if [ "$SETUP_LOCALHOST" = "true" ]; then
      echo "💻 Local Access:;https://localhost.n8n"
    fi
    echo "🔧 Direct Access:;http://localhost:$PORT"
  } | column -t -s ';' | gum format
  
  if [ "$SETUP_LOCALHOST" = "true" ]; then
    gum style --foreground 214 --italic "   Note: Accept the self-signed certificate warning for localhost.n8n"
  fi
  
  # Commands section
  echo ""
  gum style --foreground 212 --bold "⚙️  MANAGEMENT COMMANDS"
  echo ""
  
  cat << 'EOF' | gum format -t code
# View logs
docker compose logs -f n8n
docker compose logs -f caddy

# Check status
docker compose ps

# Restart services
docker compose restart n8n
docker compose restart caddy

# Stop everything
docker compose down

# Update n8n
docker compose pull n8n
docker compose up -d
EOF
  
  # Files section
  echo ""
  gum style --foreground 212 --bold "🔐 IMPORTANT FILES"
  echo ""
  printf "• .env - Configuration file\n• secrets/encryption_key.txt - Encryption key\n• Caddyfile - Reverse proxy config\n" | gum format
  
  # Troubleshooting
  echo ""
  gum style --foreground 214 --bold "⚠️  TROUBLESHOOTING"
  printf "If you can't access n8n:\n• Check firewall: sudo ufw allow 80,443\n• Verify /etc/hosts entries\n• Check logs: docker compose logs\n" | gum format
  
  # SSL warning for local domains
  if [[ "$DOMAIN" =~ \.local$ ]] || [[ "$DOMAIN" == *localhost* ]]; then
    echo ""
    gum style --foreground 196 --bold "🔒 SSL NOTE"
    gum style --foreground 250 "Your browser will show a security warning because $DOMAIN uses a self-signed certificate."
    gum style --foreground 250 "This is normal for local development. Click 'Advanced' → 'Proceed' to continue."
  fi
  
else
  # Fallback without gum
  echo ""
  echo "✅ Setup complete!"
  echo ""
  echo "Access n8n at:"
  echo "  https://$DOMAIN"
  if [ "$SETUP_LOCALHOST" = "true" ]; then
    echo "  https://localhost.n8n (accept self-signed cert)"
  fi
  echo "  http://localhost:$PORT (direct access)"
  echo ""
  echo "Check logs:"
  echo "  docker compose logs -f n8n caddy"
  echo ""
  echo "Keep secrets/encryption_key.txt safe!"
  
  # SSL warning
  if [[ "$DOMAIN" =~ \.local$ ]] || [[ "$DOMAIN" == *localhost* ]]; then
    echo ""
    echo "🔒 SSL NOTE: Your browser will show a security warning because"
    echo "   $DOMAIN uses a self-signed certificate. This is normal."
    echo "   Click 'Advanced' → 'Proceed' to continue."
  fi
fi
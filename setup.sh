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

# ========================
# Installation Detection
# ========================
detect_installation() {
    if [ -f .env ] && [ -f docker-compose.yml ] && docker compose ps 2>/dev/null | grep -q n8n; then
        echo "existing"
    elif [ -f .env ] || [ -f docker-compose.yml ]; then
        echo "partial"
    else
        echo "fresh"
    fi
}

# ========================
# Initialize
# ========================
rotate_logs() {
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
    : > "$LOG_FILE"
}

log() { 
    if command -v gum >/dev/null 2>&1; then
        gum log -t "[$(date '+%H:%M:%S')]" "$@" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
    fi
}

run() {
    if $DRY_RUN; then
        log "[DRY-RUN] $*"
    else
        eval "$@" | tee -a "$LOG_FILE"
    fi
}

# Start fresh
rotate_logs

# ========================
# Welcome Banner
# ========================
show_banner() {
    clear
    if command -v gum >/dev/null 2>&1; then
        gum style \
            --foreground 212 --border-foreground 212 --border double \
            --align center --width 70 --margin "1 2" --padding "2 4" \
            '🚀 n8n Enterprise Deployment' \
            'Automated Production-Ready Setup'
    else
        echo ""
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║             🚀 n8n Enterprise Deployment            ║"
        echo "║           Automated Production-Ready Setup           ║"
        echo "╚══════════════════════════════════════════════════════╝"
        echo ""
    fi
}

show_banner
log "Starting n8n deployment process..."

# ========================
# Check existing installation
# ========================
INSTALL_STATE=$(detect_installation)
case "$INSTALL_STATE" in
    "existing")
        if command -v gum >/dev/null 2>&1; then
            gum confirm "n8n appears to be already running. Continue anyway?" && \
                gum log -t "[INFO]" "Continuing with existing installation..." || exit 0
        else
            read -rp "n8n appears to be already running. Continue anyway? (y/N): " answer
            [[ "$answer" =~ ^[Yy]$ ]] || exit 0
        fi
        ;;
    "partial")
        log "⚠️  Found partial installation. Will attempt to continue..."
        ;;
esac

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
    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) log "❌ Unsupported arch for Gum: $ARCH"; return 1 ;;
    esac
    
    # Try package manager first
    case "$DISTRO" in
        ubuntu|debian)
            run "sudo mkdir -p /etc/apt/keyrings"
            run "curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg"
            run 'echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list'
            run "sudo apt update && sudo apt install -y gum"
            ;;
        rocky|almalinux|centos|rhel|fedora)
            run 'echo "[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key" | sudo tee /etc/yum.repos.d/charm.repo'
            run "sudo dnf install -y gum"
            ;;
        arch)
            run "sudo pacman -S --noconfirm gum"
            ;;
        *)
            # Fallback to direct download
            local GUM_VERSION
            GUM_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest | grep tag_name | cut -d'"' -f4)
            run "sudo curl -L https://github.com/charmbracelet/gum/releases/download/${GUM_VERSION}/gum_${GUM_VERSION#v}_linux_${ARCH}.tar.gz | sudo tar -xz -C /usr/local/bin"
            ;;
    esac
    
    if ! command -v gum >/dev/null 2>&1; then
        log "⚠️  Failed to install Gum, will use basic prompts"
        return 1
    fi
    
    log "✅ Gum installed successfully"
}

# ========================
# Ensure dependencies
# ========================
log "🔧 Ensuring dependencies..."
for dep in curl awk sed grep getent openssl jq; do install_pkg "$dep"; done
install_docker
run "sudo systemctl enable --now docker || true"
install_compose_plugin
install_gum

# ========================
# Docker group access
# ========================
ensure_docker_access() {
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        log "User $USER is not in docker group"
        
        if command -v gum >/dev/null 2>&1; then
            gum style --foreground 196 --bold "⚠️  DOCKER PERMISSIONS REQUIRED"
            gum confirm "Add $USER to docker group?" && {
                run "sudo usermod -aG docker $USER"
                gum style --foreground 212 --bold "✅ Added to docker group!"
                gum style --foreground 214 "🔁 You must log out and back in, or run: " --background 235 --padding "0 1" "newgrp docker"
                gum style --foreground 214 "   Then re-run this script."
                exit 0
            } || {
                gum style --foreground 196 "❌ Docker permissions required to continue."
                exit 1
            }
        else
            echo ""
            echo "⚠️  User $USER is not in docker group"
            read -rp "Add to docker group? (Y/n): " answer
            answer=${answer:-Y}
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                run "sudo usermod -aG docker $USER"
                echo ""
                echo "✅ Added to docker group!"
                echo "➡ You must log out and back in, or run: newgrp docker"
                echo "➡ Then re-run this script."
                exit 0
            else
                echo "❌ Docker permissions required to continue."
                exit 1
            fi
        fi
    fi
    log "✅ Docker permissions verified"
}

ensure_docker_access

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
# Domain Configuration
# ========================
configure_domains() {
    local primary_domain=""
    local setup_localhost=true
    
    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 --bold "🌐 DOMAIN CONFIGURATION"
        gum style --foreground 250 "Configure how you'll access n8n:"
        echo ""
        
        # Ask for primary domain
        primary_domain=$(gum input --placeholder "n8n.local" --value "n8n.local" \
            --prompt.foreground 39 --prompt "Enter primary domain: " \
            --header "Leave as 'n8n.local' for local testing or enter your actual domain")
        
        # Ask about localhost access
        gum confirm "Setup localhost.n8n alias for local access?" && setup_localhost=true || setup_localhost=false
        
        # Ask about adding to /etc/hosts
        if [[ "$primary_domain" == *.local ]] || [[ "$primary_domain" == localhost* ]]; then
            gum confirm "Add $primary_domain to /etc/hosts for local resolution?" && {
                echo "127.0.0.1 $primary_domain" | sudo tee -a /etc/hosts
                log "✅ Added $primary_domain to /etc/hosts"
            }
        fi
        
    else
        echo ""
        echo "🌐 DOMAIN CONFIGURATION"
        echo ""
        read -rp "Enter primary domain [n8n.local]: " primary_domain
        primary_domain=${primary_domain:-n8n.local}
        
        read -rp "Setup localhost.n8n alias for local access? [Y/n]: " local_answer
        local_answer=${local_answer:-Y}
        [[ "$local_answer" =~ ^[Yy]$ ]] && setup_localhost=true || setup_localhost=false
        
        if [[ "$primary_domain" == *.local ]] || [[ "$primary_domain" == localhost* ]]; then
            read -rp "Add $primary_domain to /etc/hosts? [Y/n]: " hosts_answer
            hosts_answer=${hosts_answer:-Y}
            [[ "$hosts_answer" =~ ^[Yy]$ ]] && {
                echo "127.0.0.1 $primary_domain" | sudo tee -a /etc/hosts
                log "✅ Added $primary_domain to /etc/hosts"
            }
        fi
    fi
    
    # Return values
    echo "$primary_domain"
    echo "$setup_localhost"
}

log "Configuring access domains..."
DOMAIN_CONFIG=$(configure_domains)
PRIMARY_DOMAIN=$(echo "$DOMAIN_CONFIG" | head -1)
SETUP_LOCALHOST=$(echo "$DOMAIN_CONFIG" | tail -1)

# ========================
# Port Configuration
# ========================
configure_port() {
    local port=""
    
    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 --bold "🔌 PORT CONFIGURATION"
        port=$(gum input --placeholder "5678" --value "5678" \
            --prompt.foreground 39 --prompt "Enter n8n port: " \
            --header "Port n8n will listen on internally")
        
        # Validate port
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
            gum style --foreground 196 "❌ Invalid port. Using default 5678."
            port="5678"
        fi
    else
        echo ""
        echo "🔌 PORT CONFIGURATION"
        read -rp "Enter n8n port [5678]: " port
        port=${port:-5678}
    fi
    
    # Check if port is in use
    if ss -tuln | grep -q ":$port "; then
        if command -v gum >/dev/null 2>&1; then
            gum style --foreground 196 "❌ Port $port is already in use!"
            port=$(gum choose --height 5 --cursor.foreground 39 \
                "5679" "5680" "5681" "Custom port" --header "Choose alternative port:")
            
            if [ "$port" = "Custom port" ]; then
                port=$(gum input --placeholder "Enter custom port" --prompt "Port: ")
            fi
        else
            echo "❌ Port $port is already in use!"
            echo "Choose alternative port:"
            select alt_port in "5679" "5680" "5681" "Custom"; do
                case $alt_port in
                    "Custom")
                        read -rp "Enter custom port: " port
                        break
                        ;;
                    *)
                        port=$alt_port
                        break
                        ;;
                esac
            done
        fi
    fi
    
    echo "$port"
}

log "Configuring port..."
PORT=$(configure_port)

# ========================
# Security Configuration
# ========================
configure_security() {
    local encryption_key=""
    
    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 39 --bold "🔐 SECURITY CONFIGURATION"
        gum style --foreground 250 "Encryption key for n8n data protection:"
        echo ""
        
        local choice
        choice=$(gum choose --height 3 --cursor.foreground 39 \
            "Generate new key" \
            "Use existing key" \
            --header "Encryption key options:")
        
        case "$choice" in
            "Generate new key")
                encryption_key=$(openssl rand -base64 32 | tr -d '\n' | head -c 32)
                log "✅ Generated new encryption key"
                ;;
            "Use existing key")
                if [ -f secrets/encryption_key.txt ]; then
                    encryption_key=$(cat secrets/encryption_key.txt)
                    log "Using existing encryption key"
                else
                    gum style --foreground 196 "❌ No existing key found. Generating new one."
                    encryption_key=$(openssl rand -base64 32 | tr -d '\n' | head -c 32)
                fi
                ;;
        esac
    else
        echo ""
        echo "🔐 SECURITY CONFIGURATION"
        echo ""
        if [ -f secrets/encryption_key.txt ]; then
            read -rp "Use existing encryption key? [Y/n]: " use_existing
            use_existing=${use_existing:-Y}
            if [[ "$use_existing" =~ ^[Yy]$ ]]; then
                encryption_key=$(cat secrets/encryption_key.txt)
                log "Using existing encryption key"
            else
                encryption_key=$(openssl rand -base64 32 | tr -d '\n' | head -c 32)
                log "✅ Generated new encryption key"
            fi
        else
            encryption_key=$(openssl rand -base64 32 | tr -d '\n' | head -c 32)
            log "✅ Generated new encryption key"
        fi
    fi
    
    # Save key
    mkdir -p secrets
    echo "$encryption_key" > secrets/encryption_key.txt
    chmod 600 secrets/encryption_key.txt
    
    echo "$encryption_key"
}

log "Configuring security..."
ENCRYPTION_KEY=$(configure_security)

# ========================
# Generate Configuration Files
# ========================
log "📄 Generating configuration files..."

# Generate .env with proper n8n settings
cat > .env <<EOF
# Domain Configuration
DOMAIN=$PRIMARY_DOMAIN
PORT=$PORT
SETUP_LOCALHOST=$SETUP_LOCALHOST

# n8n Configuration
N8N_VERSION=$N8N_VERSION
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
N8N_PROTOCOL=https
N8N_HOST=$PRIMARY_DOMAIN
N8N_PORT=443
WEBHOOK_URL=https://$PRIMARY_DOMAIN

# Database Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
POSTGRES_DB=n8n

# System Configuration
UID=$(id -u)
GID=$(id -g)
TZ=${TZ:-$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")}
EOF

log "✅ .env file generated"

# Generate Caddyfile based on domain configuration
generate_caddyfile() {
    local primary_domain="$1"
    local port="$2"
    local setup_localhost="$3"
    
    cat > Caddyfile <<EOF
# n8n Reverse Proxy Configuration
# Generated: $(date)

# Primary domain
$primary_domain {
    # Redirect HTTP to HTTPS
    @http {
        protocol http
    }
    redir @http https://{host}{uri} permanent
    
    # HTTPS configuration
    @https {
        protocol https
    }
    handle @https {
        reverse_proxy n8n:$port {
            header_up Host {host}
            header_up X-Forwarded-Proto https
            header_up X-Real-IP {remote}
        }
    }
}
EOF
    
    # Add localhost alias if requested
    if [ "$setup_localhost" = "true" ]; then
        cat >> Caddyfile <<EOF

# Local development alias (self-signed certificate)
localhost.n8n {
    tls internal
    reverse_proxy n8n:$port {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}
EOF
        # Add to /etc/hosts if not already there
        if ! grep -q "localhost.n8n" /etc/hosts 2>/dev/null; then
            echo "127.0.0.1 localhost.n8n" | sudo tee -a /etc/hosts >/dev/null
            log "✅ Added localhost.n8n to /etc/hosts"
        fi
    fi
    
    # Add catch-all for IP access
    cat >> Caddyfile <<EOF

# IP-based access (for direct IP access)
:80, :443 {
    @ip not host *.*
    handle @ip {
        reverse_proxy n8n:$port {
            header_up Host $primary_domain
            header_up X-Forwarded-Proto {scheme}
        }
    }
    
    # Default response for other hosts
    respond "n8n is running. Access via: $primary_domain${setup_localhost:+, localhost.n8n, or server IP}" 200
}
EOF
    
    log "✅ Caddyfile generated"
}

generate_caddyfile "$PRIMARY_DOMAIN" "$PORT" "$SETUP_LOCALHOST"

# Copy docker-compose template
[ -f docker-compose.yml.template ] || { log "❌ docker-compose.yml.template missing"; exit 1; }
run "cp docker-compose.yml.template docker-compose.yml"

# ========================
# Setup Persistent Data
# ========================
log "📁 Setting up persistent data directories..."

mkdir -p data/{n8n,postgres,redis,caddy,caddy-config} logs

log "🔐 Setting directory permissions..."
run "sudo chown -R $UID:$GID data logs 2>/dev/null || true"
run "chmod 750 data logs"
run "chmod 700 data/n8n"

# Test write access
if touch data/n8n/.write_test 2>/dev/null; then
    rm data/n8n/.write_test
    log "✅ Write permissions verified"
else
    log "⚠️  Write permission issues detected, adjusting..."
    run "sudo chown -R $UID:$GID data"
fi

# ========================
# Start Deployment
# ========================
if command -v gum >/dev/null 2>&1; then
    gum style --foreground 39 --bold "🚀 DEPLOYMENT STARTING"
    gum spin --spinner dot --title "Starting n8n stack..." -- \
        docker compose up -d
else
    log "🚀 Starting n8n stack..."
    run "docker compose up -d"
fi

# ========================
# Health Checks
# ========================
check_health() {
    local service="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local attempt=1
    
    if command -v gum >/dev/null 2>&1; then
        gum spin --spinner line --title "Waiting for $service..." --show-output -- \
            while [ $attempt -le $max_attempts ]; do
                if curl -f -s "$url" >/dev/null 2>&1; then
                    gum style --foreground 46 "✅ $service is healthy"
                    return 0
                fi
                sleep 2
                attempt=$((attempt + 1))
            done
        gum style --foreground 196 "❌ $service failed to start"
        return 1
    else
        log "⏳ Waiting for $service to become healthy..."
        while [ $attempt -le $max_attempts ]; do
            if curl -f -s "$url" >/dev/null 2>&1; then
                log "✅ $service is healthy"
                return 0
            fi
            sleep 2
            attempt=$((attempt + 1))
        done
        log "❌ $service failed to start"
        return 1
    fi
}

# Check n8n health
check_health "n8n" "http://localhost:$PORT/healthz" 60

# Check Caddy health
if [ "$SETUP_LOCALHOST" = "true" ]; then
    check_health "Caddy (localhost)" "https://localhost.n8n/healthz" 30
else
    check_health "Caddy" "http://$PRIMARY_DOMAIN" 30
fi

# ========================
# Final Summary
# ========================
show_summary() {
    local primary_domain="$1"
    local port="$2"
    local setup_localhost="$3"
    
    if command -v gum >/dev/null 2>&1; then
        clear
        gum style \
            --foreground 46 --border-foreground 46 --border double \
            --align center --width 70 --margin "1 2" --padding "2 4" \
            '🎉 n8n DEPLOYMENT COMPLETE' \
            'Your automation platform is ready!'
        
        echo ""
        gum style --foreground 39 --bold "🔗 ACCESS URLs:"
        echo ""
        
        # Primary domain access
        gum style --foreground 255 --background 24 --padding "0 2" --margin "0 1" \
            "🌐 Primary Domain: " --foreground 39 --bold "https://$primary_domain"
        
        # Localhost access if enabled
        if [ "$setup_localhost" = "true" ]; then
            gum style --foreground 255 --background 24 --padding "0 2" --margin "1 1" \
                "💻 Local Access:    " --foreground 39 --bold "https://localhost.n8n"
            gum style --foreground 214 --margin "0 1" \
                "   Note: Accept the self-signed certificate warning"
        fi
        
        # Direct access
        gum style --foreground 255 --background 24 --padding "0 2" --margin "1 1" \
            "🔧 Direct Access:   " --foreground 39 --bold "http://localhost:$port"
        
        echo ""
        gum style --foreground 39 --bold "⚙️  MANAGEMENT COMMANDS:"
        echo ""
        
        cat <<EOF | gum format -t code
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
        
        echo ""
        gum style --foreground 39 --bold "🔐 IMPORTANT FILES:"
        echo ""
        gum style --foreground 250 "• .env - Configuration file"
        gum style --foreground 250 "• secrets/encryption_key.txt - Encryption key (KEEP SAFE!)"
        gum style --foreground 250 "• Caddyfile - Reverse proxy configuration"
        
        echo ""
        gum style --foreground 214 --bold "⚠️  NEXT STEPS:"
        gum style --foreground 250 "1. Visit the URL above to create your first user"
        gum style --foreground 250 "2. Configure your workflows"
        gum style --foreground 250 "3. Set up backups (check docs)"
        
        echo ""
        gum style --foreground 196 --bold "❌ TROUBLESHOOTING:"
        gum style --foreground 250 "If you can't access n8n:"
        gum style --foreground 250 "• Check firewall: sudo ufw allow 80,443"
        gum style --foreground 250 "• Verify DNS/hosts file entries"
        gum style --foreground 250 "• Check logs: docker compose logs"
        
    else
        echo ""
        echo "🎉 n8n DEPLOYMENT COMPLETE"
        echo "═══════════════════════════════════════════════════"
        echo ""
        echo "🔗 ACCESS URLs:"
        echo ""
        echo "  🌐 Primary Domain: https://$primary_domain"
        if [ "$setup_localhost" = "true" ]; then
            echo "  💻 Local Access:    https://localhost.n8n"
            echo "     Note: Accept the self-signed certificate warning"
        fi
        echo "  🔧 Direct Access:   http://localhost:$port"
        echo ""
        echo "⚙️  MANAGEMENT COMMANDS:"
        echo ""
        echo "  # View logs"
        echo "  docker compose logs -f n8n"
        echo "  docker compose logs -f caddy"
        echo ""
        echo "  # Check status"
        echo "  docker compose ps"
        echo ""
        echo "  # Stop everything"
        echo "  docker compose down"
        echo ""
        echo "🔐 IMPORTANT FILES:"
        echo ""
        echo "  • .env - Configuration file"
        echo "  • secrets/encryption_key.txt - Encryption key (KEEP SAFE!)"
        echo "  • Caddyfile - Reverse proxy configuration"
        echo ""
        echo "⚠️  NEXT STEPS:"
        echo "  1. Visit the URL above to create your first user"
        echo "  2. Configure your workflows"
        echo "  3. Set up backups"
        echo ""
    fi
}

show_summary "$PRIMARY_DOMAIN" "$PORT" "$SETUP_LOCALHOST"

# ========================
# Verify Everything Works
# ========================
log ""
log "🧪 Running final verification..."

# Test direct access
if curl -s http://localhost:$PORT/healthz >/dev/null; then
    log "✅ n8n direct access working"
else
    log "⚠️  n8n direct access issue detected"
fi

# Test Caddy access
if [ "$SETUP_LOCALHOST" = "true" ]; then
    if curl -k -s https://localhost.n8n/healthz >/dev/null; then
        log "✅ Caddy localhost access working"
    else
        log "⚠️  Caddy localhost access issue"
    fi
fi

log ""
log "✅ Setup completed successfully!"
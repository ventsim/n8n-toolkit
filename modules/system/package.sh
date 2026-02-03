#!/usr/bin/env bash
# modules/system/package.sh - Package management

# Install system package
install_pkg() {
    local pkg="$1"
    local distro="${2:-$(detect_distro)}"
    
    # Check if already installed
    if command -v "$pkg" >/dev/null 2>&1; then
        log_info "$pkg already installed"
        return 0
    fi
    
    log "Installing $pkg..."
    
    case "$distro" in
        ubuntu|debian|raspbian)
            run "sudo apt-get update -y"
            run "sudo apt-get install -y $pkg"
            ;;
        centos|rhel|rocky|almalinux)
            run "sudo dnf install -y $pkg"
            ;;
        fedora)
            run "sudo dnf install -y $pkg"
            ;;
        arch|manjaro)
            run "sudo pacman -Sy --noconfirm $pkg"
            ;;
        alpine)
            run "sudo apk add --no-cache $pkg"
            ;;
        *)
            log_fatal "Unsupported distribution: $distro"
            ;;
    esac
}

# Install Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker already installed"
        return 0
    fi
    
    log "Installing Docker..."
    
    # Use official Docker install script
    if $DRY_RUN; then
        log "[DRY-RUN] Would run: curl -fsSL https://get.docker.com | sudo sh"
    else
        curl -fsSL https://get.docker.com | sudo sh
    fi
    
    # Enable and start Docker service
    run "sudo systemctl enable --now docker 2>/dev/null || true"
    run "sudo usermod -aG docker $(whoami) 2>/dev/null || true"
    
    log_success "Docker installed"
}

# Install Docker Compose plugin
install_compose_plugin() {
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose plugin already installed"
        return 0
    fi
    
    log "Installing Docker Compose plugin..."
    
    local arch
    arch=$(detect_architecture)
    
    # Map architecture names
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        armv7) arch="armv7" ;;
        *) log_fatal "Unsupported architecture: $arch" ;;
    esac
    
    local DEST="/usr/local/lib/docker/cli-plugins"
    run "sudo mkdir -p $DEST"
    
    # Get latest release URL
    local URL
    URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
        | grep browser_download_url \
        | grep "linux-$arch" \
        | cut -d '"' -f 4)
    
    if [ -z "$URL" ]; then
        log_fatal "Failed to detect Docker Compose download URL"
    fi
    
    run "sudo curl -L $URL -o $DEST/docker-compose"
    run "sudo chmod +x $DEST/docker-compose"
    
    log_success "Docker Compose plugin installed"
}

# Install Gum
install_gum() {
    if command -v gum >/dev/null 2>&1; then
        log_info "Gum already installed"
        return 0
    fi
    
    log "Installing Gum..."
    
    local arch
    arch=$(detect_architecture)
    
    # Map architecture for Gum
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) 
            log_warn "Unsupported architecture for Gum: $arch"
            return 1
            ;;
    esac
    
    # Get latest version
    local GUM_VERSION
    GUM_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest \
        | grep tag_name \
        | cut -d'"' -f4 2>/dev/null || echo "v0.13.0")
    
    local download_url="https://github.com/charmbracelet/gum/releases/download/${GUM_VERSION}/gum_${GUM_VERSION#v}_linux_${arch}.tar.gz"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would download Gum from: $download_url"
    else
        # Download and install
        local temp_dir
        temp_dir=$(mktemp -d)
        
        if curl -fsSL "$download_url" -o "$temp_dir/gum.tar.gz"; then
            sudo tar -xzf "$temp_dir/gum.tar.gz" -C /usr/local/bin gum
            sudo chmod +x /usr/local/bin/gum
            rm -rf "$temp_dir"
            
            if command -v gum >/dev/null 2>&1; then
                log_success "Gum installed successfully"
                return 0
            fi
        fi
        
        log_warn "Failed to install Gum, will use basic prompts"
        return 1
    fi
}

# Install Node.js (optional, for future use)
install_node() {
    local version="${1:-18}"
    
    if command -v node >/dev/null 2>&1; then
        log_info "Node.js already installed"
        return 0
    fi
    
    log "Installing Node.js $version..."
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            # Using NodeSource repository
            run "curl -fsSL https://deb.nodesource.com/setup_${version}.x | sudo -E bash -"
            run "sudo apt-get install -y nodejs"
            ;;
        centos|rhel|rocky|fedora)
            run "curl -fsSL https://rpm.nodesource.com/setup_${version}.x | sudo bash -"
            run "sudo dnf install -y nodejs"
            ;;
        arch)
            run "sudo pacman -Sy --noconfirm nodejs npm"
            ;;
        *)
            log_warn "Automatic Node.js installation not supported for $distro"
            return 1
            ;;
    esac
    
    log_success "Node.js installed"
}
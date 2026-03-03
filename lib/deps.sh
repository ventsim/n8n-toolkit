#!/usr/bin/env bash

# ========================
# OS / Package / Tools
# ========================

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

install_pkg() {
  local pkg="$1"
  command -v "$pkg" >/dev/null 2>&1 && return 0

  log_info "Installing $pkg..."
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
      error "Unsupported distro: $DISTRO"
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker already installed"
    return
  fi
  log_info "Installing Docker..."
  run "curl -fsSL https://get.docker.com | sudo sh"
  run "sudo systemctl enable --now docker || true"
}

install_compose_plugin() {
  if docker compose version >/dev/null 2>&1; then
    log_info "Docker Compose plugin already installed"
    return
  fi

  log_info "Installing Docker Compose plugin..."
  local ARCH DEST URL
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) log_error "Unsupported arch: $ARCH" ;;
  esac

  DEST="/usr/local/lib/docker/cli-plugins"
  run "sudo mkdir -p $DEST"

  URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep browser_download_url \
    | grep "linux-$ARCH" \
    | cut -d '"' -f 4)

  [ -z "$URL" ] && error "Failed to detect Compose plugin URL"

  run "sudo curl -L $URL -o $DEST/docker-compose"
  run "sudo chmod +x $DEST/docker-compose"
}

install_gum() {
  if command -v gum >/dev/null 2>&1; then
    log_info "Gum already installed"
    return
  fi

  log_info "Installing Gum..."

  # Try package managers first (more reliable)
  if command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu - add charm repo
    log_info "Detected apt-based system, installing via charm repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt-get update && sudo apt-get install -y gum
  elif command -v yum >/dev/null 2>&1; then
    # RHEL/CentOS/Fedora - add charm repo
    log_info "Detected yum-based system, installing via charm repo..."
    sudo tee /etc/yum.repos.d/charm.repo <<EOF
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
    sudo yum install -y gum
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    log_info "Detected pacman-based system, installing via AUR..."
    if command -v yay >/dev/null 2>&1; then
      yay -S --noconfirm gum
    elif command -v paru >/dev/null 2>&1; then
      paru -S --noconfirm gum
    else
      log_warn "Please install gum from AUR manually (gum-bin)"
    fi
  else
    # Fallback to manual installation
    log_info "No supported package manager found, installing manually..."
    install_gum_manual
  fi

  # Verify installation
  if command -v gum >/dev/null 2>&1; then
    log_info "Gum installed successfully"
  else
    log_error "Failed to install gum"
    return 1
  fi
}

# Manual installation function (extracted from above)
install_gum_manual() {
  local ARCH GUM_VERSION TMP_DIR
  
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) log_error "Unsupported architecture: $ARCH"; return 1 ;;
  esac

  GUM_VERSION=$(curl -s --fail https://api.github.com/repos/charmbracelet/gum/releases/latest 2>/dev/null \
    | grep -Po '"tag_name": "\K[^"]*' || echo "v0.13.0")
  
  local VERSION_NUM="${GUM_VERSION#v}"
  
  TMP_DIR=$(mktemp -d)
  local TAR_FILE="${TMP_DIR}/gum.tar.gz"
  
  if ! curl -L --fail "https://github.com/charmbracelet/gum/releases/download/${GUM_VERSION}/gum_${VERSION_NUM}_linux_${ARCH}.tar.gz" -o "$TAR_FILE"; then
    log_error "Download failed"
    rm -rf "$TMP_DIR"
    return 1
  fi
  
  tar -xzf "$TAR_FILE" -C "$TMP_DIR" || { rm -rf "$TMP_DIR"; return 1; }
  sudo install -m 755 "$TMP_DIR/gum" /usr/local/bin/gum || { rm -rf "$TMP_DIR"; return 1; }
  rm -rf "$TMP_DIR"
}

ensure_dependencies() {
  log_info "Ensuring base dependencies..."
  for dep in curl awk sed grep getent openssl ss; do install_pkg "$dep"; done
  install_docker
  install_compose_plugin
  install_gum
}


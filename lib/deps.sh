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
      error "Unsupported distro: $DISTRO"
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
  run "sudo systemctl enable --now docker || true"
}

install_compose_plugin() {
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose plugin already installed"
    return
  fi

  log "Installing Docker Compose plugin..."
  local ARCH DEST URL
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) error "Unsupported arch: $ARCH" ;;
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
    log "Gum already installed"
    return
  fi

  log "Installing Gum..."
  local ARCH GUM_VERSION
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) warn "Unsupported arch for Gum"; return ;;
  esac

  GUM_VERSION=$(curl -s https://api.github.com/repos/charmbracelet/gum/releases/latest \
    | grep tag_name | cut -d'"' -f4 || echo "v0.13.0")

  run "sudo curl -L https://github.com/charmbracelet/gum/releases/download/${GUM_VERSION}/gum_${GUM_VERSION#v}_linux_${ARCH}.tar.gz -o /tmp/gum.tar.gz"
  run "sudo tar -xzf /tmp/gum.tar.gz -C /usr/local/bin gum"
  run "sudo rm -f /tmp/gum.tar.gz"
}

ensure_dependencies() {
  log "Ensuring base dependencies..."
  for dep in curl awk sed grep getent openssl ss; do install_pkg "$dep"; done
  install_docker
  install_compose_plugin
  install_gum
}


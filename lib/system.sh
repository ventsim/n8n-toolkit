#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

detect_arch() {
  uname -m
}

install_pkg() {
  local pkg="$1"
  command -v "$pkg" >/dev/null 2>&1 && return 0

  log_info "Installing package: $pkg"
  case "$DISTRO" in
    ubuntu|debian)
      sudo apt-get update -y
      sudo apt-get install -y "$pkg"
      ;;
    rocky|almalinux|centos|rhel)
      sudo dnf install -y "$pkg"
      ;;
    arch)
      sudo pacman -Sy --noconfirm "$pkg"
      ;;
    *)
      log_error "Unsupported distro: $DISTRO"
      exit 1
      ;;
  esac
}

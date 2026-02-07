#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ========================
# Distro & Arch Detection
# ========================

detect_arch() {
  uname -m
}

detect_distro() {
  local id="" id_like=""

  # 1. Preferred: /etc/os-release
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  # 2. Fallback: lsb_release
  if [ -z "$id" ] && command -v lsb_release >/dev/null 2>&1; then
    id=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
  fi

  # 3. Fallback: /etc/*release
  if [ -z "$id" ]; then
    id=$(cat /etc/*release 2>/dev/null | grep -Ei '^(ID=|DISTRIB_ID=)' | head -n1 | cut -d= -f2 | tr '[:upper:]' '[:lower:]' || true)
  fi

  # 4. Fallback: hostnamectl
  if [ -z "$id" ] && command -v hostnamectl >/dev/null 2>&1; then
    id=$(hostnamectl 2>/dev/null | grep -i "Operating System" | awk '{print tolower($3)}' || true)
  fi

  # Normalize
  case "$id" in
    ubuntu|debian|rocky|almalinux|centos|rhel|arch)
      echo "$id"
      return
      ;;
  esac

  # Try loose match using ID_LIKE
  if [ -n "$id_like" ]; then
    if echo "$id_like" | grep -qi "debian"; then echo "debian"; return; fi
    if echo "$id_like" | grep -qi "rhel";   then echo "rhel";   return; fi
    if echo "$id_like" | grep -qi "fedora"; then echo "rhel";   return; fi
    if echo "$id_like" | grep -qi "arch";   then echo "arch";   return; fi
  fi

  echo "unknown"
}

# ========================
# Package Manager Detection
# ========================

detect_pkg_manager_for_distro() {
  local distro="$1"

  case "$distro" in
    ubuntu|debian)
      command -v apt-get >/dev/null 2>&1 && echo "apt" && return
      ;;
    rocky|almalinux|centos|rhel|fedora)
      command -v dnf >/dev/null 2>&1 && echo "dnf" && return
      command -v yum >/dev/null 2>&1 && echo "yum" && return
      ;;
    arch)
      command -v pacman >/dev/null 2>&1 && echo "pacman" && return
      ;;
    opensuse*|sles)
      command -v zypper >/dev/null 2>&1 && echo "zypper" && return
      ;;
  esac

  return 1
}

detect_pkg_manager_fallback() {
  # Fallback: probe common managers
  for pm in apt-get dnf yum pacman zypper apk; do
    if command -v "$pm" >/dev/null 2>&1; then
      case "$pm" in
        apt-get) echo "apt"; return ;;
        dnf)     echo "dnf"; return ;;
        yum)     echo "yum"; return ;;
        pacman)  echo "pacman"; return ;;
        zypper)  echo "zypper"; return ;;
        apk)     echo "apk"; return ;;
      esac
    fi
  done

  echo "unknown"
}

verify_pkg_manager_for_distro() {
  local distro="$1"
  local pm

  # 1. Try expected PM for detected distro
  if pm=$(detect_pkg_manager_for_distro "$distro"); then
    log_info "Using package manager '$pm' for distro '$distro'"
    echo "$pm"
    return
  fi

  # 2. Fallback: detect any available PM
  pm=$(detect_pkg_manager_fallback)

  if [ "$pm" != "unknown" ]; then
    log_warn "Distro '$distro' did not match expected package manager — falling back to '$pm'"
    echo "$pm"
    return
  fi

  log_error "Could not detect a supported package manager on this system"
  exit 1
}

# ========================
# Package Install Helper
# ========================

install_pkg() {
  local pkg="$1"
  command -v "$pkg" >/dev/null 2>&1 && return 0

  local distro pm
  distro=$(detect_distro)
  pm=$(verify_pkg_manager_for_distro "$distro")

  log_info "Installing dependency: $pkg (via $pm)"

  case "$pm" in
    apt)
      sudo apt-get update -y
      sudo apt-get install -y "$pkg"
      ;;
    dnf)
      sudo dnf install -y "$pkg"
      ;;
    yum)
      sudo yum install -y "$pkg"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "$pkg"
      ;;
    zypper)
      sudo zypper install -y "$pkg"
      ;;
    apk)
      sudo apk add --no-cache "$pkg"
      ;;
    *)
      log_error "Unsupported package manager: $pm"
      exit 1
      ;;
  esac
}

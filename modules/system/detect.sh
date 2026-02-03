#!/usr/bin/env bash
# modules/system/detect.sh - System detection

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Detect system architecture
detect_architecture() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|x64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armhf)
            echo "armv7"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Detect available package manager
detect_package_manager() {
    local distro="$1"
    
    case "$distro" in
        ubuntu|debian|raspbian)
            echo "apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            echo "dnf"
            ;;
        arch|manjaro)
            echo "pacman"
            ;;
        alpine)
            echo "apk"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get system memory in MB
get_system_memory() {
    if command -v free >/dev/null 2>&1; then
        free -m | awk '/^Mem:/{print $2}'
    else
        echo "0"
    fi
}

# Get disk space in GB
get_disk_space() {
    if command -v df >/dev/null 2>&1; then
        df -BG / | awk 'NR==2 {print $4}' | sed 's/G//'
    else
        echo "0"
    fi
}

# Check if running as root
is_root() {
    [ "$EUID" -eq 0 ]
}

# Get current username
get_username() {
    whoami
}
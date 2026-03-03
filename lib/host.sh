#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

check_port() {
  local port="$1"
  if ss -tuln | grep -q ":$port "; then
    log_warn "Port $port is already in use"
    return 1
  fi
}

check_dns() {
  local host="$1"
  local ip
  ip=$(getent hosts "$host" | awk '{print $1}' || true)
  [ -z "$ip" ] && return 1 || return 0
}

add_hosts_entry() {
  local host="$1"
  if ! grep -q "$host" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
    log_info "Added $host to /etc/hosts"
  fi
}

ensure_docker_group() {
  if ! groups "$USER" | grep -q 'docker'; then
    log_warn "User not in docker group, adding..."
    sudo usermod -aG docker "$USER"
    log_info "Re-login required. Running: exec su - USER "
    exec su - "$USER"   
   # log_error "Re-login required. Run: newgrp docker"
    exit 0
  fi
}
create_service_user() {
  local user="n8nsvc"
  if ! id "$user" &>/dev/null; then
    log_info "Creating service user: $user"
    sudo useradd -r -m -d /opt/n8n -s /usr/sbin/nologin "$user"
  fi
}
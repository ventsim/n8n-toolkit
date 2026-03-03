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
  if id -nG "$USER" | grep -qw docker; then
    DOCKER_CMD="docker"
    return
  fi

  log_warn "User '$USER' is not in the docker group."
  log_info "Adding user to docker group..."
  sudo usermod -aG docker "$USER"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Docker group membership updated."
  echo "You must log out and log back in"
  echo "to use Docker without sudo."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Use sudo for this session
  DOCKER_CMD="sudo docker"
}

create_service_user() {
  local user="n8nsvc"
  if ! id "$user" &>/dev/null; then
    log_info "Creating service user: $user"
    sudo useradd -r -m -d /opt/n8n -s /usr/sbin/nologin "$user"
  fi
}
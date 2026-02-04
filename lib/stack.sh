#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

install_docker() {
  command -v docker >/dev/null 2>&1 && return
  log_info "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker || true
}

install_compose_plugin() {
  docker compose version >/dev/null 2>&1 && return

  log_info "Installing Docker Compose plugin..."
  local ARCH DEST URL
  ARCH=$(uname -m)
  DEST="/usr/local/lib/docker/cli-plugins"

  mkdir -p "$DEST"

  URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep browser_download_url | grep "linux-$ARCH" | cut -d '"' -f 4)

  [ -z "$URL" ] && { log_error "Compose URL detection failed"; exit 1; }

  curl -L "$URL" -o "$DEST/docker-compose"
  chmod +x "$DEST/docker-compose"
}

start_stack() {
  log_info "Starting services..."
  docker compose up -d
}

wait_for_container() {
  local name="$1" timeout="${2:-60}"
  for i in $(seq 1 "$timeout"); do
    if docker ps --format '{{.Names}} {{.Status}}' | grep -q "^$name.*Up"; then
      log_info "$name is running"
      return 0
    fi
    sleep 1
  done
  log_warn "$name did not start in time"
  return 1
}

#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

detect_latest_n8n() {
  curl -s 'https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100' \
    | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
    | sed 's/"name":"//;s/"//' \
    | sort -Vr | head -n1
}

generate_compose() {
  local version="$1"
  local port="$2"
  local domain="$3"
  local encryption_key="$4"

  log_info "Generating docker-compose.yml..."

  if [ ! -f docker-compose.yml.template ]; then
    log_error "docker-compose.yml.template not found"
    exit 1
  fi

  sed -e "s|{{N8N_VERSION}}|$version|g" \
      -e "s|{{PORT}}|$port|g" \
      -e "s|{{DOMAIN}}|$domain|g" \
      -e "s|{{ENCRYPTION_KEY}}|$encryption_key|g" \
      -e "s|{{UID}}|$(id -u)|g" \
      -e "s|{{GID}}|$(id -g)|g" \
      docker-compose.yml.template > docker-compose.yml

  log_info "docker-compose.yml generated"
}

generate_caddy() {
  local port="$1"
  local domain="$2"
  local setup_localhost="$3"

  log_info "Generating Caddyfile..."

  if [ "$setup_localhost" = "true" ]; then

    cat > Caddyfile <<EOF
$domain {
    reverse_proxy n8n:$port
}

localhost.n8n {
    tls internal
    reverse_proxy n8n:$port
}
EOF

  else

    if [ ! -f Caddyfile.template ]; then
      log_error "Caddyfile.template not found"
      exit 1
    fi

    sed -e "s|{{DOMAIN}}|$domain|g" \
        -e "s|{{PORT}}|$port|g" \
        Caddyfile.template > Caddyfile
  fi

  log_info "Caddyfile generated"
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

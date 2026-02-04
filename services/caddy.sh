#!/usr/bin/env bash

# ========================
# Caddy Service Logic
# ========================

caddy_prepare_dirs() {
  mkdir -p data/caddy data/caddy-config
  run "sudo chown -R $(id -u):$(id -g) data/caddy data/caddy-config"
}

caddy_healthcheck() {
  log "Checking Caddy container..."
  docker ps --format "{{.Names}} {{.Status}}" | grep -q "^caddy.*Up" \
    && log "✅ Caddy is running" \
    || warn "⚠️  Caddy not running"
}

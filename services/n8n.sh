#!/usr/bin/env bash

# ========================
# n8n Service Logic
# ========================

n8n_prepare_dirs() {
  mkdir -p data/n8n
  run "sudo chown -R $(id -u):$(id -g) data/n8n"
}

n8n_healthcheck() {
  log "Checking n8n container..."
  docker ps --format "{{.Names}} {{.Status}}" | grep -q "^n8n.*Up" \
    && log "✅ n8n is running" \
    || warn "⚠️  n8n not running"
}

#!/usr/bin/env bash
set -Eeuo pipefail

# ========================
# Core Runtime / Logging
# ========================

LOG_FILE="logs/setup.log"
OLD_LOG_FILE="logs/setup.log.prev"
DRY_RUN=false
NON_INTERACTIVE=false

init_runtime() {
  mkdir -p logs
  rotate_logs
}

rotate_logs() {
  [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
  : > "$LOG_FILE"
}

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

warn() {
  log "⚠️  $*"
}

error() {
  log "❌ $*"
  exit 1
}

run() {
  if $DRY_RUN; then
    log "[DRY-RUN] $*"
  else
    eval "$@" | tee -a "$LOG_FILE"
  fi
}

parse_flags() {
  for arg in "$@"; do
    case $arg in
      --dry-run) DRY_RUN=true ;;
      --non-interactive) NON_INTERACTIVE=true ;;
    esac
  done
}


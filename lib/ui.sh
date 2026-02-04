#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="${LOG_FILE:-setup.log}"

log_info()  { echo "[$(date '+%F %T')] [INFO]  $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo "[$(date '+%F %T')] [WARN]  $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%F %T')] [ERROR] $*" | tee -a "$LOG_FILE"; }

prompt() {
  local __var="$1" text="$2" def="$3"
  if $NON_INTERACTIVE; then
    eval "$__var=\"$def\""
    log_info "Using default for $__var=$def"
  else
    if command -v gum >/dev/null 2>&1; then
      local val
      val=$(gum input --value "$def" --prompt "$text ")
      val="${val:-$def}"
      eval "$__var=\"$val\""
    else
      read -rp "$text [$def]: " val
      val="${val:-$def}"
      eval "$__var=\"$val\""
    fi
  fi
}

ui_header() {
  command -v gum >/dev/null 2>&1 || return 0
  clear
  gum style --border double --padding "2 4" --width 70 --align center "$@"
}

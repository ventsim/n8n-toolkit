#!/usr/bin/env bash

# Color theme (lime green)
THEME_FG=46
THEME_BORDER=46
WARN_FG=214
ERROR_FG=196
INFO_FG=82

log_raw() {
  echo "[$(date '+%F %T')] $*" >> setup.log
}

log_info() {
  log_raw "INFO: $*"
  if command -v gum >/dev/null; then
    gum style --foreground $INFO_FG "ℹ $*"
  else
    echo "ℹ $*"
  fi
}

log_warn() {
  log_raw "WARN: $*"
  if command -v gum >/dev/null; then
    gum style --foreground $WARN_FG "⚠ $*"
  else
    echo "⚠ $*"
  fi
}

log_error() {
  log_raw "ERROR: $*"
  if command -v gum >/dev/null; then
    gum style --foreground $ERROR_FG "✖ $*"
  else
    echo "✖ $*"
  fi
}

ui_header() {
  command -v gum >/dev/null || return
  clear
  gum style \
    --foreground $THEME_FG --border-foreground $THEME_BORDER --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    "$1" "$2"
}

ui_spin() {
  if command -v gum >/dev/null; then
    gum spin --spinner dot --title "$1" -- "$2"
  else
    eval "$2"
  fi
}

ui_confirm() {
  if command -v gum >/dev/null; then
    gum confirm "$1"
  else
    read -rp "$1 [Y/n]: " r
    [[ "${r:-Y}" =~ ^[Yy]$ ]]
  fi
}

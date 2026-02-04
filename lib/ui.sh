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
 if command -v gum >/dev/null 2>&1; then
    clear
    gum style \
    --foreground $THEME_FG --border-foreground $THEME_BORDER --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    "$1" "$2"
 fi
}

ui_run() {
  if command -v gum >/dev/null; then
    gum spin --spinner dot --title "$1" -- "$2"
  else
    eval "$2"
  fi
}

ui_run() {
  local label="$1"; shift
  if command -v gum >/dev/null 2>&1; then
    gum spin --spinner dot --title "$label" -- "$@"
  else
    echo "→ $label..."
    "$@"
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

prompt() {
  local var="$1" text="$2" def="$3"
  if command -v gum >/dev/null 2>&1; then
    local val
    val=$(gum input --prompt "$text: " --value "$def")
    eval "$var=\"${val:-$def}\""
  else
    read -rp "$text [$def]: " val
    eval "$var=\"${val:-$def}\""
  fi
}

ui_license() {
  clear
  cat <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 n8n Stage 1 – Lean Stack Installer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This script will:

• Install Docker & Docker Compose
• Generate encryption keys
• Create config files
• Start containers on your system

You are responsible for:
• Securing your data
• Backing up secrets
• Using this in non-production environments

THIS SOFTWARE IS PROVIDED "AS IS"
WITHOUT WARRANTY OF ANY KIND.

EOF

  if ! ui_confirm "Do you accept this license and want to continue?"; then
    log_error "License not accepted. Exiting."
    exit 1
  fi
}

ui_final_screen() {
  if ! command -v gum >/dev/null 2>&1; then
    echo "✅ Setup complete!"
    echo "Access n8n at: https://$DOMAIN"
    return
  fi

  clear
  gum style \
    --foreground 46 --border-foreground 46 --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    '✅ n8n DEPLOYMENT COMPLETE' \
    'Your automation platform is ready!'

  echo ""
  gum style --foreground 82 --bold "🔗 ACCESS URLS"
  {
    echo "🌐 Primary Domain:;https://$DOMAIN"
    [ "$SETUP_LOCALHOST" = "true" ] && echo "💻 Local Alias:;https://localhost.n8n"
    echo "🔧 Direct Access:;http://localhost:$PORT"
  } | column -t -s ';' | gum format

  echo ""
  gum style --foreground 82 --bold "⚙️ MANAGEMENT"
  cat << 'EOF' | gum format -t code
docker compose ps
docker compose logs -f n8n
docker compose restart n8n
docker compose down
EOF

  echo ""
  gum style --foreground 214 --bold "🔐 IMPORTANT FILES"
  printf "• .env\n• secrets/encryption_key.txt\n• Caddyfile\n" | gum format
}

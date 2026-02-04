#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="setup.log"
OLD_LOG_FILE="setup.log.prev"

[ -f "$LOG_FILE" ] && mv "$LOG_FILE" "$OLD_LOG_FILE"
: > "$LOG_FILE"

source lib/ui.sh
source lib/system.sh
source lib/env.sh
source lib/host.sh
source lib/stack.sh

log_info "🚀 n8n Stage 1 Lean Setup Starting"

DISTRO=$(detect_distro)
ARCH=$(detect_arch)
log_info "Detected distro: $DISTRO"
log_info "Detected arch: $ARCH"

log_info "🔧 Ensuring dependencies..."
for dep in curl awk sed grep getent openssl ss; do install_pkg "$dep"; done

install_docker
install_compose_plugin
ensure_docker_group

log_info "🔎 Detecting latest stable n8n version..."
N8N_VERSION=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100 \
  | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' | sed 's/"name":"//;s/"//' | sort -Vr | head -n1)

ui_header "🚀 n8n Deployment Setup" "Configure your installation"

prompt DOMAIN "Enter domain / IP / hostname" "n8n.local"
prompt PORT "Enter n8n internal port" "5678"

SETUP_LOCALHOST=false
command -v gum >/dev/null 2>&1 && gum confirm "Enable localhost.n8n alias?" && SETUP_LOCALHOST=true

check_port "$PORT" || log_warn "Port may already be in use"
check_dns "$DOMAIN" || log_warn "DNS not resolving (OK for local)"

command -v gum >/dev/null 2>&1 && gum confirm "Add $DOMAIN to /etc/hosts?" && add_hosts_entry "$DOMAIN"

load_or_create_secret
write_env_file

log_info "Generating configs..."
sed -e "s|{{N8N_VERSION}}|$N8N_VERSION|g" \
    -e "s|{{PORT}}|$PORT|g" \
    -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{ENCRYPTION_KEY}}|$ENCRYPTION_KEY|g" \
    -e "s|{{UID}}|$(id -u)|g" \
    -e "s|{{GID}}|$(id -g)|g" docker-compose.yml.template > docker-compose.yml

if [ "$SETUP_LOCALHOST" = "true" ]; then
cat > Caddyfile <<EOF
$DOMAIN {
    reverse_proxy n8n:$PORT
}
localhost.n8n {
    tls internal
    reverse_proxy n8n:$PORT
}
EOF
else
sed -e "s|{{DOMAIN}}|$DOMAIN|g" -e "s|{{PORT}}|$PORT|g" Caddyfile.template > Caddyfile
fi

log_info "Ensuring data directories..."
mkdir -p data/n8n data/caddy data/caddy-config logs
sudo chown -R "$(id -u):$(id -g)" data logs

start_stack
wait_for_container "n8n" 90
wait_for_container "caddy" 30

# ========================
# Final output with Gum styling (Green Theme)
# ========================
if command -v gum >/dev/null 2>&1; then
  clear

  # Header
  gum style \
    --foreground 46 --border-foreground 46 --border double \
    --align center --width 70 --margin "1 2" --padding "2 4" \
    '✅ n8n DEPLOYMENT COMPLETE' \
    'Your automation platform is ready!'

  # URLs section
  echo ""
  gum style --foreground 82 --bold "🔗 ACCESS URLs"
  echo ""

  {
    echo "🌐 Primary Domain:;https://$DOMAIN"
    if [ "$SETUP_LOCALHOST" = "true" ]; then
      echo "💻 Local Access:;https://localhost.n8n"
    fi
    echo "🔧 Direct Access:;http://localhost:$PORT"
  } | column -t -s ';' | gum format

  if [ "$SETUP_LOCALHOST" = "true" ]; then
    gum style --foreground 114 --italic "Note – Accept the self-signed certificate warning for localhost.n8n"
  fi

  # Commands section
  echo ""
  gum style --foreground 82 --bold "⚙️  MANAGEMENT COMMANDS"
  echo ""

  cat << 'EOF' | gum format -t code
# View logs
docker compose logs -f n8n
docker compose logs -f caddy

# Check status
docker compose ps

# Restart services
docker compose restart n8n
docker compose restart caddy

# Stop everything
docker compose down

# Update n8n
docker compose pull n8n
docker compose up -d

# Remove the entire stack
docker compose down
cd ~ && sudo rm -rf n8n-toolkit
EOF

  # Files section
  echo ""
  gum style --foreground 82 --bold "🔐 IMPORTANT FILES"
  echo ""
  printf "• .env - Configuration file\n• secrets/encryption_key.txt - Encryption key\n• Caddyfile - Reverse proxy config\n" | gum format

  # Troubleshooting
  echo ""
  gum style --foreground 214 --bold "⚠️  TROUBLESHOOTING"
  printf "If you can't access n8n:\n• Check firewall: sudo ufw allow 80,443\n• Verify /etc/hosts entries\n• Check logs: docker compose logs\n" | gum format

  # SSL warning for local domains
  if [[ "$DOMAIN" =~ \.local$ ]] || [[ "$DOMAIN" == *localhost* ]]; then
    echo ""
    gum style --foreground 196 --bold "🔒 SSL NOTE"
    gum style --foreground 250 "Your browser will show a security warning because $DOMAIN uses a self-signed certificate."
    gum style --foreground 250 "This is normal for local development. Click 'Advanced' → 'Proceed' to continue."
  fi

else
  # Fallback without gum
  echo ""
  echo "✅ Setup complete!"
  echo ""
  echo "Access n8n at:"
  echo "  https://$DOMAIN"
  if [ "$SETUP_LOCALHOST" = "true" ]; then
    echo "  https://localhost.n8n (accept self-signed cert)"
  fi
  echo "  http://localhost:$PORT (direct access)"
  echo ""
  echo "Check logs:"
  echo "  docker compose logs -f n8n caddy"
  echo ""
  echo "Keep secrets/encryption_key.txt safe!"

  if [[ "$DOMAIN" =~ \.local$ ]] || [[ "$DOMAIN" == *localhost* ]]; then
    echo ""
    echo "🔒 SSL NOTE: Your browser will show a security warning because"
    echo "   $DOMAIN uses a self-signed certificate. This is normal."
    echo "   Click 'Advanced' → 'Proceed' to continue."
  fi
fi


#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

STATE_FILE=".install-state.env"

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ No install state file found. Cannot safely cleanup."
  exit 1
fi

# Load state
source "$STATE_FILE"

echo "⚠️  This will remove all components installed by the n8n setup."
read -rp "Are you sure you want to proceed? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 0

echo "🛑 Stopping services..."
docker compose down || true

echo "🧹 Removing containers..."
docker rm -f n8n caddy 2>/dev/null || true

echo "🧹 Removing images..."
docker rmi n8nio/n8n caddy:2-alpine 2>/dev/null || true

# Remove directories created by setup
if [ -n "${CREATED_DIRS:-}" ]; then
  echo "🗑 Removing created directories: $CREATED_DIRS"
  rm -rf $CREATED_DIRS
fi

# Remove secrets & env
rm -f .env secrets/encryption_key.txt

# Remove hosts entry
if [ "${MODIFIED_HOSTS:-false}" = "true" ]; then
  echo "🧹 Cleaning /etc/hosts entries..."
  sudo sed -i '/n8n/d' /etc/hosts
fi

# Remove Gum if installed by script
if [ "${INSTALLED_GUM:-false}" = "true" ]; then
  echo "🗑 Removing Gum..."
  sudo rm -f /usr/local/bin/gum
fi

# Remove Docker Compose plugin
if [ "${INSTALLED_COMPOSE:-false}" = "true" ]; then
  echo "🗑 Removing Docker Compose plugin..."
  sudo rm -f /usr/local/lib/docker/cli-plugins/docker-compose
fi

# Remove Docker (ONLY if script installed it)
if [ "${INSTALLED_DOCKER:-false}" = "true" ]; then
  echo "🗑 Removing Docker..."

  if command -v apt-get >/dev/null; then
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo apt-get autoremove -y
  elif command -v dnf >/dev/null; then
    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v pacman >/dev/null; then
    sudo pacman -Rns --noconfirm docker
  fi

  sudo rm -rf /var/lib/docker /var/lib/containerd
fi

echo "🧹 Removing install state..."
rm -f "$STATE_FILE"

echo ""
echo "✅ Cleanup complete. System reverted to pre-install state."

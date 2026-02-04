#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

generate_key() {
  openssl rand -base64 32 | tr -d '\n' | head -c 32
}

write_env_file() {
  cat > .env <<EOF
DOMAIN=$DOMAIN
PORT=$PORT
N8N_VERSION=$N8N_VERSION
ENCRYPTION_KEY=$ENCRYPTION_KEY
SETUP_LOCALHOST=$SETUP_LOCALHOST
UID=$(id -u)
GID=$(id -g)
EOF

  log_info ".env file written"
}

load_or_create_secret() {
  mkdir -p secrets
  if [ ! -f secrets/encryption_key.txt ]; then
    ENCRYPTION_KEY=$(generate_key)
    echo "$ENCRYPTION_KEY" > secrets/encryption_key.txt
    chmod 600 secrets/encryption_key.txt
    log_info "Encryption key generated"
  else
    ENCRYPTION_KEY=$(cat secrets/encryption_key.txt)
    log_info "Using existing encryption key"
  fi
}

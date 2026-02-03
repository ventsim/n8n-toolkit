#!/usr/bin/env bash
# stage1/setup.sh - Stage 1: Lean Prototyping

set -Eeuo pipefail

# Load common modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Initialize
main_init "$@"

# Main execution
main() {
    show_banner "🚀 n8n Stage 1 Setup" "Lean Prototyping Deployment"
    
    log "Starting Stage 1 deployment..."
    
    # Check system
    local distro
    distro=$(detect_distro)
    log "Detected distro: $distro"
    
    # Ensure dependencies
    ensure_dependencies true
    
    # Install Gum for better UI
    install_gum || log_warn "Gum installation failed, using basic prompts"
    
    # Configure domain and port
    local DOMAIN=""
    local SETUP_LOCALHOST=false
    prompt_domain "DOMAIN" "n8n.local" "SETUP_LOCALHOST"
    
    local PORT=""
    prompt_port "PORT" "5678"
    
    # Check DNS (warning only)
    check_dns "$DOMAIN" || true
    
    # Setup secrets
    source "${MODULES_DIR}/security/secrets.sh"
    local ENCRYPTION_KEY
    ENCRYPTION_KEY=$(manage_secrets "encryption_key")
    
    # Generate .env file
    cat > .env <<EOF
DOMAIN=$DOMAIN
PORT=$PORT
SETUP_LOCALHOST=$SETUP_LOCALHOST
ENCRYPTION_KEY=$ENCRYPTION_KEY
UID=$(id -u)
GID=$(id -g)
EOF
    
    log_success ".env file created"
    
    # Get n8n version
    source "${MODULES_DIR}/services/n8n.sh"
    local N8N_VERSION
    N8N_VERSION=$(get_n8n_version)
    log "Using n8n version: $N8N_VERSION"
    
    # Generate configuration files
    source "${MODULES_DIR}/config/templates.sh"
    
    # Docker Compose
    generate_from_template \
        "${SCRIPT_DIR}/docker-compose.yml.template" \
        "docker-compose.yml" \
        "N8N_VERSION=$N8N_VERSION" \
        "PORT=$PORT" \
        "DOMAIN=$DOMAIN" \
        "ENCRYPTION_KEY=$ENCRYPTION_KEY" \
        "UID=$(id -u)" \
        "GID=$(id -g)"
    
    # Caddyfile
    if [ "$SETUP_LOCALHOST" = "true" ]; then
        generate_caddyfile_multi_domain "$DOMAIN" "$PORT" "localhost.n8n"
        add_to_hosts "localhost.n8n"
    else
        generate_caddyfile_single_domain "$DOMAIN" "$PORT"
    fi
    
    # Add primary domain to hosts if .local
    if [[ "$DOMAIN" == *.local ]]; then
        add_to_hosts "$DOMAIN"
    fi
    
    # Setup data directories
    source "${MODULES_DIR}/data/directories.sh"
    setup_data_directories
    
    # Start services
    log "Starting services..."
    if command -v gum >/dev/null 2>&1; then
        show_spinner "Starting n8n stack" docker compose up -d
    else
        docker compose up -d
    fi
    
    # Health checks
    source "${MODULES_DIR}/monitoring/health.sh"
    health_check_n8n_deployment "$DOMAIN" "$PORT" "$SETUP_LOCALHOST"
    
    # Show summary
    show_deployment_summary "$DOMAIN" "$PORT" "$SETUP_LOCALHOST"
    
    log_success "Stage 1 deployment complete!"
}

# Run main
main "$@"
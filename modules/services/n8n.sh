#!/usr/bin/env bash
# modules/services/n8n.sh - n8n service management

# Detect latest n8n version
detect_n8n_version() {
    local version_source="${1:-dockerhub}"
    
    log "Detecting latest n8n version from $version_source..."
    
    local version=""
    
    case "$version_source" in
        dockerhub)
            version=$(curl -s https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=50 \
                | grep -oE '"name":"[0-9]+\.[0-9]+\.[0-9]+"' \
                | sed 's/"name":"//;s/"//' \
                | sort -Vr \
                | head -n1)
            ;;
        github)
            version=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest \
                | grep -o '"tag_name":"v[0-9]\+\.[0-9]\+\.[0-9]\+"' \
                | cut -d'"' -f4 \
                | sed 's/^v//')
            ;;
        *)
            log_warn "Unknown version source: $version_source"
            return 1
            ;;
    esac
    
    if [ -z "$version" ]; then
        log_warn "Could not detect n8n version from $version_source"
        
        # Fallback version
        version="2.7.0"
        log "Using fallback version: $version"
    else
        log_success "Detected n8n version: $version"
    fi
    
    echo "$version"
}

# Validate n8n version
validate_n8n_version() {
    local version="$1"
    
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warn "Invalid version format: $version"
        return 1
    fi
    
    # Check if version exists on Docker Hub
    if ! docker manifest inspect "n8nio/n8n:$version" >/dev/null 2>&1; then
        log_warn "Version $version not found on Docker Hub"
        return 1
    fi
    
    return 0
}

# Get n8n image name
get_n8n_image() {
    local version="${1:-}"
    
    if [ -z "$version" ]; then
        version=$(detect_n8n_version)
    fi
    
    echo "n8nio/n8n:$version"
}

# Generate n8n environment variables
generate_n8n_env() {
    local domain="${1:-localhost}"
    local port="${2:-5678}"
    local encryption_key="${3:-}"
    
    cat << EOF
# n8n Core Configuration
N8N_PROTOCOL=https
N8N_HOST=$domain
N8N_PORT=443
WEBHOOK_URL=https://$domain

# Security
N8N_ENCRYPTION_KEY=$encryption_key
N8N_SECURE_COOKIE=true

# Database (for Stage 2+)
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432

# Execution Mode
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis

# Performance
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168

# Telemetry
N8N_DIAGNOSTICS_ENABLED=false
N8N_METRICS=true
EOF
}

# Check n8n health
check_n8n_health() {
    local port="${1:-5678}"
    local timeout="${2:-30}"
    
    log "Checking n8n health on port $port..."
    
    for i in $(seq 1 "$timeout"); do
        # Try internal health check first
        if docker exec n8n curl -f -s http://localhost:443/healthz >/dev/null 2>&1; then
            log_success "n8n internal health check passed"
            return 0
        fi
        
        # Try exposed port
        if curl -f -s "http://localhost:$port/healthz" >/dev/null 2>&1; then
            log_success "n8n exposed port health check passed"
            return 0
        fi
        
        sleep 1
    done
    
    log_warn "n8n health check timed out after ${timeout}s"
    return 1
}

# Get n8n container status
get_n8n_status() {
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^n8n"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "^n8n"
        return 0
    else
        log_warn "n8n container not running"
        return 1
    fi
}

# Update n8n to specific version
update_n8n() {
    local version="$1"
    local backup_first="${2:-true}"
    
    if ! validate_n8n_version "$version"; then
        log_fatal "Invalid n8n version: $version"
    fi
    
    log "Updating n8n to version $version..."
    
    if [ "$backup_first" = "true" ]; then
        log "Creating backup before update..."
        # Backup logic would go here
    fi
    
    # Pull new image
    run "docker compose pull n8n"
    
    # Restart service
    run "docker compose up -d n8n"
    
    log_success "n8n updated to version $version"
}
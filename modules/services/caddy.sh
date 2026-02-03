#!/usr/bin/env bash
# modules/services/caddy.sh - Caddy reverse proxy management

# Generate Caddyfile for single domain
generate_caddyfile_single() {
    local domain="$1"
    local port="$2"
    
    cat << EOF
# Primary domain: $domain
$domain {
    reverse_proxy n8n:$port {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}
EOF
}

# Generate Caddyfile with localhost alias
generate_caddyfile_multi() {
    local domain="$1"
    local port="$2"
    
    cat << EOF
# Primary domain: $domain
$domain {
    reverse_proxy n8n:$port {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}

# Local development alias
localhost.n8n {
    tls internal
    reverse_proxy n8n:$port {
        header_up Host {host}
        header_up X-Forwarded-Proto https
    }
}

# IP-based fallback
:80, :443 {
    @ip not host *.*
    handle @ip {
        reverse_proxy n8n:$port {
            header_up Host $domain
            header_up X-Forwarded-Proto {scheme}
        }
    }
}
EOF
}

# Create Caddyfile based on configuration
create_caddyfile() {
    local domain="$1"
    local port="$2"
    local setup_localhost="${3:-false}"
    local output_file="${4:-Caddyfile}"
    
    log "Creating Caddyfile for $domain..."
    
    if [ "$setup_localhost" = "true" ]; then
        generate_caddyfile_multi "$domain" "$port" > "$output_file"
        log_success "Created multi-domain Caddyfile with localhost.n8n alias"
    else
        generate_caddyfile_single "$domain" "$port" > "$output_file"
        log_success "Created single-domain Caddyfile"
    fi
}

# Configure /etc/hosts for local domains
configure_hosts_file() {
    local domain="$1"
    local add_localhost="${2:-false}"
    
    log "Configuring /etc/hosts file..."
    
    # Add primary domain if it's a .local domain
    if [[ "$domain" == *.local ]] || [[ "$domain" == localhost* ]]; then
        if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
            echo "127.0.0.1 $domain" | sudo tee -a /etc/hosts
            log_success "Added $domain to /etc/hosts"
        fi
    fi
    
    # Add localhost.n8n alias if requested
    if [ "$add_localhost" = "true" ]; then
        if ! grep -q "localhost.n8n" /etc/hosts 2>/dev/null; then
            echo "127.0.0.1 localhost.n8n" | sudo tee -a /etc/hosts
            log_success "Added localhost.n8n to /etc/hosts"
        fi
    fi
}

# Check Caddy health
check_caddy_health() {
    local domain="${1:-localhost}"
    local timeout="${2:-30}"
    local use_https="${3:-true}"
    
    log "Checking Caddy health for $domain..."
    
    for i in $(seq 1 "$timeout"); do
        if [ "$use_https" = "true" ]; then
            # Try HTTPS with self-signed cert ignore
            if curl -k -f -s "https://$domain" >/dev/null 2>&1; then
                log_success "Caddy HTTPS responding"
                return 0
            fi
        else
            # Try HTTP
            if curl -f -s "http://$domain" >/dev/null 2>&1; then
                log_success "Caddy HTTP responding"
                return 0
            fi
        fi
        
        sleep 1
    done
    
    log_warn "Caddy health check timed out after ${timeout}s"
    return 1
}

# Get Caddy container status
get_caddy_status() {
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^caddy"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "^caddy"
        return 0
    else
        log_warn "Caddy container not running"
        return 1
    fi
}

# Test SSL configuration
test_ssl_config() {
    local domain="$1"
    
    log "Testing SSL configuration for $domain..."
    
    if curl -k -I "https://$domain" 2>/dev/null | grep -q "HTTP"; then
        log_success "SSL endpoint responding"
        
        # Check certificate
        if echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
            log_success "SSL certificate found"
            return 0
        else
            log_warn "No SSL certificate found (self-signed may be in use)"
            return 1
        fi
    else
        log_warn "SSL endpoint not responding"
        return 1
    fi
}
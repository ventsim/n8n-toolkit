#!/usr/bin/env bash
# modules/security/secrets.sh - Secrets management

# Generate random key
generate_key() {
    local length="${1:-32}"
    
    # Generate random bytes and convert to base64, then trim to length
    openssl rand -base64 48 | tr -d '\n=+/' | head -c "$length"
}

# Initialize secrets directory
secrets_init() {
    local secrets_dir="${1:-secrets}"
    
    log "Initializing secrets directory..."
    
    mkdir -p "$secrets_dir"
    chmod 700 "$secrets_dir"
    
    # Create .gitignore to prevent accidental commits
    cat > "$secrets_dir/.gitignore" << 'EOF'
# DO NOT COMMIT SECRET FILES
*
!.gitignore
EOF
    
    log_success "Secrets directory ready: $secrets_dir"
}

# Save secret to file
save_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secrets_dir="${3:-secrets}"
    
    local secret_file="$secrets_dir/$secret_name.txt"
    
    echo "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"
    
    log_success "Saved secret: $secret_name"
}

# Load secret from file
load_secret() {
    local secret_name="$1"
    local secrets_dir="${2:-secrets}"
    
    local secret_file="$secrets_dir/$secret_name.txt"
    
    if [ ! -f "$secret_file" ]; then
        log_warn "Secret not found: $secret_name"
        return 1
    fi
    
    cat "$secret_file"
}

# Check if secret exists
secret_exists() {
    local secret_name="$1"
    local secrets_dir="${2:-secrets}"
    
    [ -f "$secrets_dir/$secret_name.txt" ]
}

# Generate and save encryption key
setup_encryption_key() {
    local secrets_dir="${1:-secrets}"
    local key_name="${2:-encryption_key}"
    
    if secret_exists "$key_name" "$secrets_dir"; then
        log_info "Using existing encryption key"
        load_secret "$key_name" "$secrets_dir"
        return 0
    fi
    
    log "Generating new encryption key..."
    local key
    key=$(generate_key 32)
    
    save_secret "$key_name" "$key" "$secrets_dir"
    echo "$key"
}

# Generate PostgreSQL password
setup_postgres_password() {
    local secrets_dir="${1:-secrets}"
    local password_name="${2:-postgres_password}"
    
    if secret_exists "$password_name" "$secrets_dir"; then
        log_info "Using existing PostgreSQL password"
        load_secret "$password_name" "$secrets_dir"
        return 0
    fi
    
    log "Generating PostgreSQL password..."
    local password
    password=$(generate_key 24)
    
    save_secret "$password_name" "$password" "$secrets_dir"
    echo "$password"
}

# Validate encryption key format
validate_encryption_key() {
    local key="$1"
    
    if [ -z "$key" ]; then
        log_warn "Encryption key cannot be empty"
        return 1
    fi
    
    if [ ${#key} -lt 32 ]; then
        log_warn "Encryption key must be at least 32 characters (got ${#key})"
        return 1
    fi
    
    return 0
}

# Secure delete file
secure_delete() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    # Try shred first, then rm as fallback
    if command -v shred >/dev/null 2>&1; then
        shred -u "$file" 2>/dev/null && return 0
    fi
    
    rm -f "$file"
}
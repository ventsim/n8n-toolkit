#!/usr/bin/env bash
# modules/config/templates.sh - Template processing

# Process template with variable substitution
process_template() {
    local template_file="$1"
    local output_file="$2"
    shift 2
    
    if [ ! -f "$template_file" ]; then
        log_fatal "Template file not found: $template_file"
    fi
    
    log "Processing template: $(basename "$template_file")"
    
    # Read template content
    local content
    content=$(cat "$template_file")
    
    # Apply all variable substitutions
    local var_name var_value
    for var_spec in "$@"; do
        var_name="${var_spec%%=*}"
        var_value="${var_spec#*=}"
        
        # Escape special characters for sed
        var_value=$(echo "$var_value" | sed 's/[\/&]/\\&/g')
        
        # Replace {{VAR_NAME}} with value
        content=$(echo "$content" | sed "s/{{$var_name}}/$var_value/g")
    done
    
    # Write output
    if $DRY_RUN; then
        log "[DRY-RUN] Would write to $output_file"
        echo "$content"
    else
        echo "$content" > "$output_file"
        log_success "Generated: $output_file"
    fi
}

# Generate environment file
generate_env_file() {
    local output_file="${1:-.env}"
    shift
    
    log "Generating environment file..."
    
    # Start with empty file
    : > "$output_file"
    
    # Add all variables
    local var_spec
    for var_spec in "$@"; do
        echo "$var_spec" >> "$output_file"
    done
    
    # Protect the file
    chmod 600 "$output_file" 2>/dev/null || true
    
    log_success "Environment file created: $output_file"
}

# Load environment variables from file
load_env_file() {
    local env_file="${1:-.env}"
    
    if [ ! -f "$env_file" ]; then
        log_warn "Environment file not found: $env_file"
        return 1
    fi
    
    log "Loading environment from $env_file"
    
    # Export all variables
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
    
    log_success "Environment loaded"
}

# Validate required environment variables
validate_environment() {
    local missing_vars=()
    
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_fatal "Missing required environment variables: ${missing_vars[*]}"
    fi
    
    log_success "All required environment variables set"
}

# Create .env from template variables
create_env_from_vars() {
    local output_file="${1:-.env}"
    local vars_file="${2:-}"
    
    # If vars file provided, source it
    if [ -n "$vars_file" ] && [ -f "$vars_file" ]; then
        load_env_file "$vars_file"
    fi
    
    cat > "$output_file" << 'EOF'
# n8n Deployment Configuration
# Generated: $(date)

EOF
    
    # Add all environment variables that start with N8N_, DB_, or are in our list
    local important_vars=(
        "DOMAIN" "PORT" "N8N_VERSION" "ENCRYPTION_KEY"
        "SETUP_LOCALHOST" "UID" "GID" "TZ"
    )
    
    for var in "${important_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            echo "$var=${!var}" >> "$output_file"
        fi
    done
    
    chmod 600 "$output_file"
    log_success "Created environment file: $output_file"
}
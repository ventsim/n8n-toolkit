#!/usr/bin/env bash
# modules/ui/prompts.sh - User interaction utilities

# Prompt for user input
prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local validate_func="${4:-}"
    
    if $NON_INTERACTIVE; then
        eval "$var_name=\"$default_value\""
        log "Using default for $var_name: $default_value"
        return
    fi
    
    local input_value=""
    
    while true; do
        if command -v gum >/dev/null 2>&1; then
            input_value=$(gum input \
                --placeholder "$default_value" \
                --value "$default_value" \
                --prompt "$prompt_text" \
                --width 50)
        else
            read -rp "$prompt_text [$default_value]: " input_value
        fi
        
        # Use default if empty
        input_value="${input_value:-$default_value}"
        
        # Validate if function provided
        if [ -n "$validate_func" ] && type "$validate_func" >/dev/null 2>&1; then
            if $validate_func "$input_value"; then
                break
            else
                log_warn "Invalid input, please try again"
                continue
            fi
        fi
        
        # Basic non-empty validation
        if [ -n "$input_value" ]; then
            break
        fi
    done
    
    eval "$var_name=\"$input_value\""
}

# Confirm action
confirm() {
    local prompt_text="$1"
    local default="${2:-Y}"
    
    if $NON_INTERACTIVE; then
        log "Auto-confirming: $prompt_text"
        return 0
    fi
    
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$prompt_text" && return 0 || return 1
    else
        local answer
        read -rp "$prompt_text [Y/n]: " answer
        answer=${answer:-$default}
        [[ "$answer" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# Select from options
select_option() {
    local prompt_text="$1"
    shift
    local options=("$@")
    
    if $NON_INTERACTIVE; then
        log "Auto-selecting first option: ${options[0]}"
        echo "${options[0]}"
        return
    fi
    
    if command -v gum >/dev/null 2>&1 && [ ${#options[@]} -gt 0 ]; then
        gum choose "${options[@]}" --header "$prompt_text"
    else
        echo "Select $prompt_text:" >&2
        select choice in "${options[@]}"; do
            if [ -n "$choice" ]; then
                echo "$choice"
                break
            fi
        done
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    
    # Check if it's a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_warn "Port must be a number"
        return 1
    fi
    
    # Check range
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        log_warn "Port must be between 1024 and 65535"
        return 1
    fi
    
    # Check if port is in use
    if ss -tuln 2>/dev/null | grep -q ":$port "; then
        log_warn "Port $port is already in use"
        return 1
    fi
    
    return 0
}

# Prompt for domain
prompt_domain() {
    local var_name="$1"
    local default_domain="${2:-n8n.local}"
    local setup_localhost_var="${3:-SETUP_LOCALHOST}"
    
    log "Configuring domain access..."
    
    # Get primary domain
    prompt "$var_name" "Enter domain / IP / local hostname" "$default_domain"
    
    # Ask about localhost alias
    if confirm "Setup localhost.n8n alias for local access?"; then
        eval "$setup_localhost_var=true"
    else
        eval "$setup_localhost_var=false"
    fi
    
    # Add to /etc/hosts if it's a .local domain
    local domain_value
    eval "domain_value=\"\$$var_name\""
    
    if [[ "$domain_value" == *.local ]] && confirm "Add $domain_value to /etc/hosts for local DNS resolution?"; then
        if ! grep -q "$domain_value" /etc/hosts 2>/dev/null; then
            echo "127.0.0.1 $domain_value" | sudo tee -a /etc/hosts
            log_success "Added $domain_value to /etc/hosts"
        fi
    fi
}

# Prompt for port with validation
prompt_port() {
    local var_name="$1"
    local default_port="${2:-5678}"
    local max_attempts="${3:-3}"
    
    local attempt=1
    local port_value=""
    
    while [ $attempt -le $max_attempts ]; do
        prompt "$var_name" "Enter n8n internal port" "$default_port" "validate_port"
        
        eval "port_value=\"\$$var_name\""
        
        # Re-validate
        if validate_port "$port_value"; then
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_fatal "Failed to get valid port after $max_attempts attempts"
        fi
        
        attempt=$((attempt + 1))
        log_warn "Please try again (attempt $attempt of $max_attempts)"
    done
}
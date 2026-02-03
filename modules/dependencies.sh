#!/usr/bin/env bash
# modules/dependencies.sh - Dependency checking

# Check for core dependencies
check_core_dependencies() {
    local missing_deps=()
    
    for dep in curl awk sed grep; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    log_success "Core dependencies verified"
    return 0
}

# Check Docker access
check_docker_access() {
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker not installed"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker daemon not running"
        return 1
    fi
    
    # Check if user has Docker permissions
    if ! docker ps >/dev/null 2>&1; then
        log_warn "User lacks Docker permissions"
        
        # Check if user is in docker group
        if ! groups "$(whoami)" | grep -q '\bdocker\b'; then
            log "User $(whoami) is not in docker group"
            
            if $NON_INTERACTIVE; then
                log_fatal "Cannot fix Docker permissions non-interactively"
            fi
            
            if $DRY_RUN; then
                log "[DRY-RUN] Would add user to docker group"
                return 0
            fi
            
            # Ask to add to docker group
            echo ""
            echo "Docker permissions required."
            read -rp "Add $(whoami) to docker group? [Y/n]: " answer
            answer=${answer:-Y}
            
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                run "sudo usermod -aG docker $(whoami)"
                log_success "Added to docker group. Please log out and back in."
                return 2  # Special code indicating need to re-login
            else
                log_fatal "Docker permissions required to continue"
            fi
        fi
    fi
    
    log_success "Docker access verified"
    return 0
}

# Check system requirements
check_system_requirements() {
    local min_memory=${1:-1024}  # MB
    local min_disk=${2:-10}      # GB
    
    log "Checking system requirements..."
    
    # Check memory
    local memory
    memory=$(get_system_memory)
    if [ "$memory" -lt "$min_memory" ]; then
        log_warn "Low memory: ${memory}MB (recommended: ${min_memory}MB)"
    else
        log_info "Memory: ${memory}MB ✓"
    fi
    
    # Check disk space
    local disk
    disk=$(get_disk_space)
    if [ "$disk" -lt "$min_disk" ]; then
        log_warn "Low disk space: ${disk}GB (recommended: ${min_disk}GB)"
    else
        log_info "Disk space: ${disk}GB ✓"
    fi
    
    # Check CPU cores
    local cores
    cores=$(nproc 2>/dev/null || echo "1")
    if [ "$cores" -lt 2 ]; then
        log_warn "Only $cores CPU core(s) (2+ recommended)"
    else
        log_info "CPU cores: $cores ✓"
    fi
}

# Ensure all dependencies
ensure_dependencies() {
    local install_missing="${1:-true}"
    
    log "Checking dependencies..."
    
    # Check core deps
    if ! check_core_dependencies && [ "$install_missing" = "true" ]; then
        local distro
        distro=$(detect_distro)
        
        for dep in curl awk sed grep; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                install_pkg "$dep" "$distro"
            fi
        done
    fi
    
    # Check Docker
    if ! check_docker_access; then
        if [ "$install_missing" = "true" ]; then
            install_docker
            sleep 2
            check_docker_access || log_fatal "Docker setup failed"
        else
            log_fatal "Docker required but not installed"
        fi
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        if [ "$install_missing" = "true" ]; then
            install_compose_plugin
        else
            log_fatal "Docker Compose required but not installed"
        fi
    fi
    
    log_success "All dependencies satisfied"
}
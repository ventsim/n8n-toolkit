#!/usr/bin/env bash
# modules/containers/management.sh - Container lifecycle management

# Wait for container to be running
wait_for_container() {
    local container_name="$1"
    local timeout="${2:-60}"
    local check_interval="${3:-1}"
    
    log "Waiting for container: $container_name (timeout: ${timeout}s)"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        # Check if container exists and is running
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            if docker ps --format "{{.Names}} {{.Status}}" | grep -q "^${container_name}.*Up"; then
                local elapsed
                elapsed=$(( $(date +%s) - start_time ))
                log_success "$container_name is running (started in ${elapsed}s)"
                return 0
            fi
        fi
        
        # Check timeout
        local current_time
        current_time=$(date +%s)
        if [ $(( current_time - start_time )) -ge "$timeout" ]; then
            log_warn "Timeout waiting for $container_name after ${timeout}s"
            return 1
        fi
        
        sleep "$check_interval"
    done
}

# Wait for multiple containers
wait_for_containers() {
    local containers=("$@")
    local timeout="${containers[-1]}"
    
    # Remove timeout from array if it's a number
    if [[ "$timeout" =~ ^[0-9]+$ ]]; then
        unset 'containers[${#containers[@]}-1]'
    else
        timeout=60
    fi
    
    local all_success=true
    
    for container in "${containers[@]}"; do
        if ! wait_for_container "$container" "$timeout"; then
            all_success=false
            docker logs "$container" --tail=20 2>/dev/null || true
        fi
    done
    
    if $all_success; then
        log_success "All containers are running"
        return 0
    else
        log_warn "Some containers failed to start"
        return 1
    fi
}

# Start Docker Compose stack
start_stack() {
    local compose_file="${1:-docker-compose.yml}"
    local services="${2:-}"
    
    log "Starting Docker Compose stack..."
    
    local cmd="docker compose"
    if [ -n "$compose_file" ] && [ "$compose_file" != "docker-compose.yml" ]; then
        cmd="$cmd -f $compose_file"
    fi
    
    cmd="$cmd up -d"
    
    if [ -n "$services" ]; then
        cmd="$cmd $services"
    fi
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would run: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "Stack started successfully"
        return 0
    else
        log_fatal "Failed to start stack"
    fi
}

# Stop Docker Compose stack
stop_stack() {
    local compose_file="${1:-docker-compose.yml}"
    
    log "Stopping Docker Compose stack..."
    
    local cmd="docker compose"
    if [ -n "$compose_file" ] && [ "$compose_file" != "docker-compose.yml" ]; then
        cmd="$cmd -f $compose_file"
    fi
    
    cmd="$cmd down"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would run: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "Stack stopped"
        return 0
    else
        log_warn "Failed to stop stack (some containers may still be running)"
        return 1
    fi
}

# Restart specific service
restart_service() {
    local service="$1"
    local compose_file="${2:-docker-compose.yml}"
    
    log "Restarting service: $service"
    
    local cmd="docker compose"
    if [ -n "$compose_file" ] && [ "$compose_file" != "docker-compose.yml" ]; then
        cmd="$cmd -f $compose_file"
    fi
    
    cmd="$cmd restart $service"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would run: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "Service $service restarted"
        return 0
    else
        log_warn "Failed to restart $service"
        return 1
    fi
}

# Get container logs
get_container_logs() {
    local container="$1"
    local lines="${2:-50}"
    local follow="${3:-false}"
    
    local cmd="docker logs"
    
    if [ "$follow" = "true" ]; then
        cmd="$cmd -f"
    fi
    
    cmd="$cmd --tail=$lines $container"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would run: $cmd"
        return 0
    fi
    
    eval "$cmd"
}

# Check if container is healthy
container_is_healthy() {
    local container="$1"
    
    # Check if container has health status
    local health_status
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
    
    if [ "$health_status" = "healthy" ]; then
        return 0
    elif [ "$health_status" = "no-healthcheck" ]; then
        # No health check defined, check if running
        if docker ps --format "{{.Names}} {{.Status}}" | grep -q "^${container}.*Up"; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# List all containers with status
list_containers() {
    log "Container status:"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would list containers"
        return 0
    fi
    
    docker compose ps || docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
#!/usr/bin/env bash
# modules/monitoring/health.sh - Health checks and monitoring

# Wait for container to be running
wait_for_container() {
    local container_name="$1"
    local timeout="${2:-60}"
    local check_interval="${3:-1}"
    
    log "Waiting for $container_name to start..."
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [ $(date +%s) -lt $end_time ]; do
        # Check if container exists and is running
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            if docker ps --format "{{.Names}} {{.Status}}" | grep -q "^${container_name}.*Up"; then
                log_success "$container_name is running"
                return 0
            fi
        fi
        
        sleep "$check_interval"
    done
    
    log_warn "$container_name not running after ${timeout}s"
    return 1
}

# Check container health endpoint
check_container_health() {
    local container_name="$1"
    local health_endpoint="${2:-/healthz}"
    local port="${3:-}"
    local timeout="${4:-5}"
    
    # If port is specified, try direct access
    if [ -n "$port" ]; then
        if curl -f -s --max-time "$timeout" "http://localhost:$port$health_endpoint" >/dev/null 2>&1; then
            log_info "$container_name health check passed (port $port)"
            return 0
        fi
    fi
    
    # Try internal container check
    if docker exec "$container_name" curl -f -s "http://localhost$health_endpoint" >/dev/null 2>&1; then
        log_info "$container_name internal health check passed"
        return 0
    fi
    
    # Check if process is running inside container
    if docker top "$container_name" >/dev/null 2>&1; then
        log_info "$container_name process is running (health endpoint may not be ready)"
        return 0
    fi
    
    log_warn "$container_name health check failed"
    return 1
}

# Test service accessibility
test_service_access() {
    local url="$1"
    local timeout="${2:-10}"
    local ignore_ssl="${3:-false}"
    
    log "Testing access to $url..."
    
    local curl_opts="-f -s --max-time $timeout"
    if [ "$ignore_ssl" = "true" ]; then
        curl_opts="$curl_opts -k"
    fi
    
    if curl $curl_opts "$url" >/dev/null 2>&1; then
        log_success "Service accessible at $url"
        return 0
    fi
    
    # Try with different methods if first fails
    if curl $curl_opts -I "$url" >/dev/null 2>&1; then
        log_info "Service responding at $url (HEAD request)"
        return 0
    fi
    
    # Try without SSL if HTTPS failed
    if [[ "$url" == https://* ]]; then
        local http_url="http://${url#https://}"
        if curl -f -s --max-time "$timeout" "$http_url" >/dev/null 2>&1; then
            log_info "Service accessible via HTTP (will redirect to HTTPS)"
            return 0
        fi
    fi
    
    log_warn "Service not accessible at $url"
    return 1
}

# Wait for multiple services
wait_for_services() {
    local -n services_array="$1"
    local timeout="${2:-120}"
    
    log "Waiting for services to start..."
    
    local all_healthy=false
    local start_time
    start_time=$(date +%s)
    
    while [ $(date +%s) -lt $((start_time + timeout)) ]; do
        all_healthy=true
        
        for service in "${services_array[@]}"; do
            IFS=':' read -r container port <<< "$service"
            
            if ! wait_for_container "$container" 2 >/dev/null; then
                all_healthy=false
                continue
            fi
            
            # Try health check if container is running
            if [ -n "$port" ]; then
                if ! check_container_health "$container" "/healthz" "$port" 2 >/dev/null; then
                    all_healthy=false
                fi
            fi
        done
        
        if $all_healthy; then
            log_success "All services are healthy"
            return 0
        fi
        
        sleep 2
    done
    
    log_warn "Some services not healthy after ${timeout}s"
    return 1
}

# Check system resources
check_system_resources() {
    local warning_threshold="${1:-80}"  # Percentage
    
    log "Checking system resources..."
    
    # CPU load
    local load
    load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cores
    cores=$(nproc)
    
    if (( $(echo "$load > $cores" | bc -l 2>/dev/null || echo "0") )); then
        log_warn "High CPU load: $load (cores: $cores)"
    else
        log_info "CPU load: $load (cores: $cores) ✓"
    fi
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local total_mem
        total_mem=$(free -m | awk '/^Mem:/{print $2}')
        local used_mem
        used_mem=$(free -m | awk '/^Mem:/{print $3}')
        local mem_percent
        mem_percent=$((used_mem * 100 / total_mem))
        
        if [ "$mem_percent" -gt "$warning_threshold" ]; then
            log_warn "High memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB)"
        else
            log_info "Memory usage: ${mem_percent}% (${used_mem}MB/${total_mem}MB) ✓"
        fi
    fi
    
    # Disk usage
    if command -v df >/dev/null 2>&1; then
        local disk_percent
        disk_percent=$(df / --output=pcent | tail -1 | tr -d '% ')
        
        if [ "$disk_percent" -gt "$warning_threshold" ]; then
            log_warn "High disk usage: ${disk_percent}%"
        else
            log_info "Disk usage: ${disk_percent}% ✓"
        fi
    fi
}

# Monitor container logs for errors
monitor_container_logs() {
    local container_name="$1"
    local timeout="${2:-30}"
    local error_pattern="${3:-error|fail|exception}"
    
    log "Monitoring $container_name logs for errors..."
    
    local start_time
    start_time=$(date +%s)
    
    while [ $(date +%s) -lt $((start_time + timeout)) ]; do
        # Get recent logs
        local logs
        logs=$(docker logs --tail=10 "$container_name" 2>&1 | grep -i -E "$error_pattern" || true)
        
        if [ -n "$logs" ]; then
            log_warn "Found errors in $container_name logs:"
            echo "$logs" | while read -r line; do
                log_warn "  $line"
            done
            return 1
        fi
        
        sleep 2
    done
    
    log_info "No errors found in $container_name logs"
    return 0
}

# Get container status summary
get_container_status() {
    local services=("$@")
    
    log "Container Status Summary:"
    
    for service in "${services[@]}"; do
        IFS=':' read -r container port <<< "$service"
        
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local status
            status=$(docker ps --format "{{.Names}} {{.Status}} {{.Ports}}" | grep "^${container}")
            log_info "  $status"
        else
            log_warn "  $container: Not running"
        fi
    done
}

# Health check n8n deployment
health_check_n8n_deployment() {
    local domain="$1"
    local port="$2"
    local setup_localhost="${3:-false}"
    
    log "Performing health checks..."
    
    # Services to check
    local services=("n8n:$port" "caddy:" "n8n-postgres:" "n8n-redis:")
    
    # Wait for core services
    wait_for_services services 60
    
    # Test primary domain access
    test_service_access "https://$domain" 10 true
    
    # Test localhost alias if enabled
    if [ "$setup_localhost" = "true" ]; then
        test_service_access "https://localhost.n8n" 5 true
    fi
    
    # Test direct access
    test_service_access "http://localhost:$port" 5 false
    
    # Check system resources
    check_system_resources 85
    
    # Get status summary
    get_container_status "${services[@]}"
    
    log_success "Health checks completed"
}

# Quick health check
quick_health_check() {
    local domain="$1"
    
    log "Quick health check..."
    
    # Check if containers are running
    local containers_running=true
    
    for container in n8n caddy; do
        if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log_warn "$container not running"
            containers_running=false
        fi
    done
    
    if ! $containers_running; then
        log_warn "Some containers not running"
        return 1
    fi
    
    # Quick accessibility test
    if timeout 5 curl -k -s "https://$domain" >/dev/null 2>&1; then
        log_success "n8n is accessible"
        return 0
    fi
    
    log_warn "n8n not accessible via HTTPS"
    return 1
}
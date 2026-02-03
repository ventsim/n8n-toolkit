#!/usr/bin/env bash
# modules/network/dns.sh - DNS and network utilities

# Check DNS resolution for a host
check_dns() {
    local host="$1"
    local max_attempts="${2:-3}"
    
    log "Checking DNS for $host..."
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        # Try different DNS lookup methods
        local ip=""
        
        # Method 1: getent hosts (uses /etc/hosts and DNS)
        if command -v getent >/dev/null 2>&1; then
            ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1)
        fi
        
        # Method 2: dig (if available)
        if [ -z "$ip" ] && command -v dig >/dev/null 2>&1; then
            ip=$(dig +short "$host" 2>/dev/null | head -1)
        fi
        
        # Method 3: nslookup
        if [ -z "$ip" ] && command -v nslookup >/dev/null 2>&1; then
            ip=$(nslookup "$host" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
        fi
        
        # Method 4: ping (for local resolution)
        if [ -z "$ip" ] && command -v ping >/dev/null 2>&1; then
            if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
                ip="resolved_via_ping"
            fi
        fi
        
        if [ -n "$ip" ] && [ "$ip" != "resolved_via_ping" ]; then
            log_success "DNS OK: $host resolves to $ip"
            return 0
        elif [ "$ip" = "resolved_via_ping" ]; then
            log_info "$host is reachable (ping successful)"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            sleep 1
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_warn "DNS for $host not resolving yet (OK for local use)"
    return 1
}

# Add entry to /etc/hosts
add_to_hosts() {
    local host="$1"
    local ip="${2:-127.0.0.1}"
    
    # Check if already exists
    if grep -q "$host" /etc/hosts 2>/dev/null; then
        log_info "$host already in /etc/hosts"
        return 0
    fi
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would add to /etc/hosts: $ip $host"
        return 0
    fi
    
    # Backup original
    if [ ! -f /etc/hosts.bak ]; then
        sudo cp /etc/hosts /etc/hosts.bak
    fi
    
    # Add entry
    if echo "$ip $host" | sudo tee -a /etc/hosts >/dev/null; then
        log_success "Added $host to /etc/hosts"
        return 0
    else
        log_warn "Failed to add $host to /etc/hosts"
        return 1
    fi
}

# Remove entry from /etc/hosts
remove_from_hosts() {
    local host="$1"
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would remove from /etc/hosts: $host"
        return 0
    fi
    
    if sudo sed -i "/$host/d" /etc/hosts 2>/dev/null; then
        log_success "Removed $host from /etc/hosts"
        return 0
    else
        log_warn "Failed to remove $host from /etc/hosts"
        return 1
    fi
}

# Check if port is available
check_port_available() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_warn "Invalid port number: $port"
        return 1
    fi
    
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_warn "Port out of range: $port"
        return 1
    fi
    
    # Check if port is in use
    local check_cmd=""
    
    if command -v ss >/dev/null 2>&1; then
        check_cmd="ss -tuln"
    elif command -v netstat >/dev/null 2>&1; then
        check_cmd="netstat -tuln"
    elif command -v lsof >/dev/null 2>&1; then
        check_cmd="lsof -i :$port"
    else
        log_warn "No port checking tool available (ss/netstat/lsof)"
        return 0  # Assume available if we can't check
    fi
    
    if eval "$check_cmd" 2>/dev/null | grep -q ":$port "; then
        log_warn "Port $port/$protocol is already in use"
        return 1
    fi
    
    log_info "Port $port/$protocol is available"
    return 0
}

# Find available port
find_available_port() {
    local start_port="${1:-5678}"
    local end_port="${2:-5688}"
    local protocol="${3:-tcp}"
    
    log "Looking for available port between $start_port and $end_port..."
    
    for port in $(seq "$start_port" "$end_port"); do
        if check_port_available "$port" "$protocol"; then
            echo "$port"
            return 0
        fi
    done
    
    log_warn "No available ports found in range $start_port-$end_port"
    echo ""
    return 1
}

# Get local IP addresses
get_local_ips() {
    local ipv4_only="${1:-false}"
    
    if command -v ip >/dev/null 2>&1; then
        if [ "$ipv4_only" = "true" ]; then
            ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'
        else
            ip addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1'
        fi
    elif command -v ifconfig >/dev/null 2>&1; then
        if [ "$ipv4_only" = "true" ]; then
            ifconfig 2>/dev/null | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'
        else
            ifconfig 2>/dev/null | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'
        fi
    else
        hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || echo ""
    fi
}

# Test network connectivity
test_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    local timeout="${3:-5}"
    
    log "Testing connectivity to $host:$port..."
    
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            log_success "Network connectivity OK"
            return 0
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout "$timeout" bash -c "echo -e '\x1dclose\x0d' | telnet $host $port" 2>/dev/null | grep -q "Connected"; then
            log_success "Network connectivity OK"
            return 0
        fi
    else
        # Fallback to ping for basic check
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            log_info "Basic connectivity OK (ping)"
            return 0
        fi
    fi
    
    log_warn "Network connectivity test failed"
    return 1
}
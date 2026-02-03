#!/usr/bin/env bash
# modules/data/directories.sh - Data directory management

# Create persistent data directories
create_data_directories() {
    local base_dir="${1:-data}"
    local user_id="${2:-$(id -u)}"
    local group_id="${3:-$(id -g)}"
    
    log "Creating persistent data directories..."
    
    # Core directories
    local directories=(
        "$base_dir/n8n"
        "$base_dir/caddy"
        "$base_dir/caddy-config"
        "$base_dir/postgres"
        "$base_dir/redis"
        "logs"
    )
    
    # Create directories
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        fi
    done
    
    # Set permissions
    chown -R "$user_id:$group_id" "$base_dir" "logs" 2>/dev/null || true
    chmod 750 "$base_dir" 2>/dev/null || true
    chmod 700 "$base_dir/n8n" 2>/dev/null || true
    
    log_success "Data directories created with appropriate permissions"
}

# Verify write permissions
verify_write_permissions() {
    local test_dir="${1:-data/n8n}"
    
    log "Verifying write permissions..."
    
    local test_file="$test_dir/.write_test_$(date +%s)"
    
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        log_success "Write permissions verified for $test_dir"
        return 0
    else
        log_warn "Cannot write to $test_dir"
        
        # Try to fix permissions
        local user_id group_id
        user_id=$(id -u)
        group_id=$(id -g)
        
        log "Attempting to fix permissions..."
        chown -R "$user_id:$group_id" "$(dirname "$test_dir")" 2>/dev/null || true
        
        if touch "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            log_success "Fixed permissions for $test_dir"
            return 0
        else
            log_fatal "Cannot write to $test_dir even after fixing permissions"
        fi
    fi
}

# Check disk space for data directories
check_disk_space() {
    local data_dir="${1:-data}"
    local required_gb="${2:-10}"
    
    log "Checking disk space for $data_dir..."
    
    if [ ! -d "$data_dir" ]; then
        mkdir -p "$data_dir"
    fi
    
    # Get available space in GB
    local available_gb
    available_gb=$(df -BG "$data_dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ -z "$available_gb" ] || [ "$available_gb" -lt "$required_gb" ]; then
        log_warn "Low disk space: ${available_gb}GB available, ${required_gb}GB recommended"
        return 1
    fi
    
    log_success "Disk space: ${available_gb}GB available ✓"
    return 0
}

# Create backup directory structure
create_backup_directories() {
    local backup_dir="${1:-backups}"
    local retention_days="${2:-30}"
    
    log "Setting up backup directories..."
    
    local directories=(
        "$backup_dir/daily"
        "$backup_dir/weekly"
        "$backup_dir/monthly"
        "$backup_dir/logs"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_success "Created backup directory: $dir"
    done
    
    # Create backup retention file
    cat > "$backup_dir/retention_policy.txt" << EOF
# Backup Retention Policy
# Created: $(date)

Daily backups: Keep $retention_days days
Weekly backups: Keep 4 weeks
Monthly backups: Keep 12 months

Directory structure:
- daily/    : Daily incremental backups
- weekly/   : Weekly full backups  
- monthly/  : Monthly full backups
- logs/     : Backup logs
EOF
    
    log_success "Backup directory structure created"
}

# Clean up old data
cleanup_old_data() {
    local data_dir="${1:-data}"
    local days_old="${2:-30}"
    
    log "Cleaning up data older than $days_old days..."
    
    if $DRY_RUN; then
        log "[DRY-RUN] Would clean up old data in $data_dir"
        return 0
    fi
    
    # Find and delete old files (modification time)
    find "$data_dir" -type f -mtime "+$days_old" -delete 2>/dev/null || true
    
    # Remove empty directories
    find "$data_dir" -type d -empty -delete 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Get directory sizes
get_directory_sizes() {
    local base_dir="${1:-data}"
    
    log "Directory sizes in $base_dir:"
    
    if command -v du >/dev/null 2>&1; then
        du -sh "$base_dir"/* 2>/dev/null || true
    else
        log_warn "du command not available, cannot show directory sizes"
    fi
}
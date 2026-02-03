#!/usr/bin/env bash
# modules/logging.sh - Logging utilities

LOG_FILE="${LOG_FILE:-setup.log}"
OLD_LOG_FILE="${OLD_LOG_FILE:-setup.log.prev}"
DRY_RUN="${DRY_RUN:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

# Initialize logging
logging_init() {
    local log_file="${1:-$LOG_FILE}"
    LOG_FILE="$log_file"
    OLD_LOG_FILE="${log_file}.prev"
    
    # Create log directory if needed
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Rotate if exists
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "$OLD_LOG_FILE"
    fi
    
    : > "$LOG_FILE"
}

# Log with timestamp
log() {
    local timestamp
    timestamp=$(date '+%F %T')
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

# Execute command with logging
run() {
    if $DRY_RUN; then
        log "[DRY-RUN] $*"
    else
        log "[EXEC] $*"
        eval "$@" 2>&1 | tee -a "$LOG_FILE"
        return ${PIPESTATUS[0]}
    fi
}

# Log error and exit
log_fatal() {
    log "❌ $*"
    exit 1
}

# Log warning
log_warn() {
    log "⚠️  $*"
}

# Log success
log_success() {
    log "✅ $*"
}

# Log info
log_info() {
    log "ℹ️  $*"
}

# Set dry run mode
set_dry_run() {
    DRY_RUN=true
    log "Dry run mode enabled"
}

# Set non-interactive mode
set_non_interactive() {
    NON_INTERACTIVE=true
    log "Non-interactive mode enabled"
}
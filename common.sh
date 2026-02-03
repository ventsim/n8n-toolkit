#!/usr/bin/env bash
# common.sh - Common module loader and utilities

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# Load a module
load_module() {
    local module="$1"
    local module_path="${MODULES_DIR}/${module}"
    
    if [ ! -f "$module_path" ]; then
        echo "❌ Module not found: $module_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$module_path"
}

# Load all core modules
load_core_modules() {
    load_module "logging.sh"
    load_module "system/detect.sh"
    load_module "system/package.sh"
    load_module "dependencies.sh"
    load_module "ui/prompts.sh"
    load_module "ui/output.sh"
    load_module "security/secrets.sh"
    load_module "config/templates.sh"
    load_module "services/n8n.sh"
    load_module "services/caddy.sh"
    load_module "containers/management.sh"
    load_module "data/directories.sh"
    load_module "network/dns.sh"
    load_module "monitoring/health.sh"
}

# Initialize logging with defaults
init_logging() {
    local log_file="${1:-setup.log}"
    logging_init "$log_file"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                set_dry_run
                shift
                ;;
            --non-interactive)
                set_non_interactive
                shift
                ;;
            --log-file=*)
                local log_file="${1#*=}"
                init_logging "$log_file"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                echo "❌ Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
n8n Deployment Framework

Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run           Simulate actions without making changes
  --non-interactive   Run without user prompts (use defaults)
  --log-file=FILE     Specify log file (default: setup.log)
  --help, -h          Show this help message
  --version, -v       Show version information

Modules:
  The framework is organized into reusable modules located in:
  ${MODULES_DIR}

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --non-interactive --log-file=deploy.log
EOF
}

# Show version
show_version() {
    echo "n8n Deployment Framework v1.0.0"
    echo "Modular deployment system for n8n automation platform"
}

# Check if running in a terminal
is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# Main initialization
main_init() {
    # Load core modules
    load_core_modules
    
    # Parse arguments
    parse_args "$@"
    
    # Initialize logging if not already done
    if [ -z "$LOG_INITIALIZED" ]; then
        init_logging
    fi
    
    log "n8n Deployment Framework initialized"
}

# Export useful functions
export -f load_module
export -f load_core_modules
export -f init_logging
export -f parse_args
export -f show_help
export -f show_version
export -f is_interactive
export -f main_init

# Export module directories
export SCRIPT_DIR
export MODULES_DIR
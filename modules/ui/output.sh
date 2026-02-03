#!/usr/bin/env bash
# modules/ui/output.sh - Output formatting and display

# Show banner
show_banner() {
    local title="$1"
    local subtitle="$2"
    
    if command -v gum >/dev/null 2>&1; then
        gum style \
            --foreground 212 --border-foreground 212 --border double \
            --align center --width 70 --margin "1 2" --padding "2 4" \
            "$title" "$subtitle"
    else
        echo ""
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║             $(echo "$title" | awk '{printf "%-44s", $0}') ║"
        echo "║             $(echo "$subtitle" | awk '{printf "%-44s", $0}') ║"
        echo "╚══════════════════════════════════════════════════════╝"
        echo ""
    fi
}

# Show success message
show_success() {
    local title="$1"
    local message="$2"
    
    if command -v gum >/dev/null 2>&1; then
        gum style \
            --foreground 46 --border-foreground 46 --border double \
            --align center --width 70 --margin "1 2" --padding "2 4" \
            "$title" "$message"
    else
        echo ""
        echo "✅ $title"
        echo "══════════════════════════════════════════════════════"
        echo "$message"
        echo ""
    fi
}

# Show error message
show_error() {
    local title="$1"
    local message="$2"
    
    if command -v gum >/dev/null 2>&1; then
        gum style \
            --foreground 196 --border-foreground 196 --border double \
            --align center --width 70 --margin "1 2" --padding "2 4" \
            "$title" "$message"
    else
        echo ""
        echo "❌ $title"
        echo "══════════════════════════════════════════════════════"
        echo "$message"
        echo ""
    fi
}

# Show section header
show_section() {
    local title="$1"
    
    if command -v gum >/dev/null 2>&1; then
        echo ""
        gum style --foreground 39 --bold "$title"
        echo ""
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  $title"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
}

# Display URLs in a nice format
show_urls() {
    local primary_url="$1"
    local local_url="$2"
    local direct_url="$3"
    
    show_section "🔗 ACCESS URLs"
    
    if command -v gum >/dev/null 2>&1; then
        {
            echo "🌐 Primary Domain:;$primary_url"
            if [ -n "$local_url" ]; then
                echo "💻 Local Access:;$local_url"
            fi
            if [ -n "$direct_url" ]; then
                echo "🔧 Direct Access:;$direct_url"
            fi
        } | column -t -s ';' | gum format
        
        if [ -n "$local_url" ]; then
            gum style --foreground 214 --italic "Note - Accept the self-signed certificate warning for localhost.n8n"
        fi
    else
        echo ""
        echo "Access n8n at:"
        echo "  $primary_url"
        if [ -n "$local_url" ]; then
            echo "  $local_url (accept self-signed cert)"
        fi
        if [ -n "$direct_url" ]; then
            echo "  $direct_url (direct access)"
        fi
        echo ""
        
        if [ -n "$local_url" ]; then
            echo "Note: Browser will show SSL warning for localhost.n8n"
            echo "      Click 'Advanced' → 'Proceed' to continue."
            echo ""
        fi
    fi
}

# Display management commands
show_management_commands() {
    local service_name="${1:-n8n}"
    
    show_section "⚙️  MANAGEMENT COMMANDS"
    
    if command -v gum >/dev/null 2>&1; then
        cat <<EOF | gum format -t code
# View logs
docker compose logs -f $service_name
docker compose logs -f caddy

# Check status
docker compose ps

# Restart services
docker compose restart $service_name
docker compose restart caddy

# Stop everything
docker compose down

# Update $service_name
docker compose pull $service_name
docker compose up -d
EOF
    else
        echo "# View logs"
        echo "docker compose logs -f $service_name"
        echo "docker compose logs -f caddy"
        echo ""
        echo "# Check status"
        echo "docker compose ps"
        echo ""
        echo "# Restart services"
        echo "docker compose restart $service_name"
        echo "docker compose restart caddy"
        echo ""
        echo "# Stop everything"
        echo "docker compose down"
        echo ""
        echo "# Update $service_name"
        echo "docker compose pull $service_name"
        echo "docker compose up -d"
        echo ""
    fi
}

# Display important files
show_important_files() {
    local files=("$@")
    
    show_section "🔐 IMPORTANT FILES"
    
    if command -v gum >/dev/null 2>&1; then
        for file in "${files[@]}"; do
            echo "• $file" | gum format
        done
    else
        for file in "${files[@]}"; do
            echo "  • $file"
        done
        echo ""
    fi
}

# Display troubleshooting tips
show_troubleshooting() {
    local tips=("$@")
    
    show_section "⚠️  TROUBLESHOOTING"
    
    if command -v gum >/dev/null 2>&1; then
        for tip in "${tips[@]}"; do
            echo "• $tip" | gum format
        done
    else
        for tip in "${tips[@]}"; do
            echo "  • $tip"
        done
        echo ""
    fi
}

# Display SSL warning for local domains
show_ssl_warning() {
    local domain="$1"
    
    if [[ "$domain" =~ \.local$ ]] || [[ "$domain" == *localhost* ]]; then
        show_section "🔒 SSL NOTE"
        
        if command -v gum >/dev/null 2>&1; then
            gum style --foreground 250 "Your browser will show a security warning because $domain uses a self-signed certificate."
            gum style --foreground 250 "This is normal for local development. Click 'Advanced' → 'Proceed' to continue."
        else
            echo "SSL NOTE: Your browser will show a security warning because"
            echo "   $domain uses a self-signed certificate. This is normal."
            echo "   Click 'Advanced' → 'Proceed' to continue."
            echo ""
        fi
    fi
}

# Show final deployment summary
show_deployment_summary() {
    local primary_domain="$1"
    local port="$2"
    local setup_localhost="${3:-false}"
    
    local primary_url="https://$primary_domain"
    local local_url=""
    local direct_url="http://localhost:$port"
    
    if [ "$setup_localhost" = "true" ]; then
        local_url="https://localhost.n8n"
    fi
    
    clear
    
    show_success "✅ n8n DEPLOYMENT COMPLETE" "Your automation platform is ready!"
    
    show_urls "$primary_url" "$local_url" "$direct_url"
    
    show_management_commands "n8n"
    
    show_important_files \
        ".env - Configuration file" \
        "secrets/encryption_key.txt - Encryption key (KEEP SAFE!)" \
        "Caddyfile - Reverse proxy configuration"
    
    show_troubleshooting \
        "If you can't access n8n:" \
        "• Check firewall: sudo ufw allow 80,443" \
        "• Verify /etc/hosts entries" \
        "• Check logs: docker compose logs"
    
    show_ssl_warning "$primary_domain"
}

# Show spinner with message
show_spinner() {
    local message="$1"
    shift
    
    if command -v gum >/dev/null 2>&1; then
        gum spin --spinner dot --title "$message" -- "$@"
    else
        echo -n "$message... "
        "$@" >/dev/null 2>&1
        echo "✓"
    fi
}
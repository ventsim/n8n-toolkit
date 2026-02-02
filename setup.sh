# ========================
# Health check
# ========================
log "⏳ Waiting for n8n to become healthy..."

# Function to check n8n health (internal container access)
check_n8n_internal() {
    # Try to access n8n health endpoint directly via Docker network
    for i in {1..30}; do
        if docker exec n8n curl -f -s http://localhost:443/healthz >/dev/null 2>&1; then
            log "✅ n8n internal health check passed"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Function to check via exposed port (if needed)
check_n8n_exposed() {
    # Try direct access via exposed port (may not work if n8n is configured for 443)
    for i in {1..10}; do
        if curl -f -s http://localhost:$PORT/healthz >/dev/null 2>&1; then
            log "✅ n8n exposed port check passed"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Check n8n health (try multiple methods)
if check_n8n_internal; then
    log "✅ n8n is running inside container"
elif check_n8n_exposed; then
    log "✅ n8n is accessible via exposed port"
else
    # Check if n8n container is at least running
    if docker ps | grep -q "n8n.*Up"; then
        log "⚠️  n8n container is running but health check failing."
        log "This may be normal - n8n might still be initializing"
    else
        log "❌ n8n container is not running"
        docker compose logs n8n --tail=20
    fi
fi

# Check Caddy via HTTPS (with self-signed cert ignore)
log "⏳ Checking Caddy proxy..."
for i in {1..30}; do
    # Use -k to ignore SSL warnings, --retry for resilience
    if curl -k -f -s --retry 2 --retry-delay 1 https://$DOMAIN/healthz >/dev/null 2>&1; then
        log "✅ Caddy proxy working (https://$DOMAIN)"
        break
    fi
    if [ $i -eq 10 ]; then
        log "⚠️  Caddy still starting..."
    fi
    if [ $i -eq 20 ]; then
        log "⚠️  Caddy taking longer than expected..."
        # Try HTTP fallback
        if curl -f -s --max-time 5 http://$DOMAIN >/dev/null 2>&1; then
            log "✅ Caddy responding on HTTP (will redirect to HTTPS)"
        fi
    fi
    sleep 2
done

# Check localhost alias if enabled
if [ "$SETUP_LOCALHOST" = "true" ]; then
    log "⏳ Checking localhost alias..."
    for i in {1..15}; do
        if curl -k -f -s https://localhost.n8n/healthz >/dev/null 2>&1; then
            log "✅ Caddy localhost alias working (https://localhost.n8n)"
            break
        fi
        sleep 2
    done
fi

# Final verification - try to access n8n UI through Caddy
log "⏳ Final verification..."
for i in {1..10}; do
    # Check if we get any response from n8n UI (not just health endpoint)
    if curl -k -s -o /dev/null -w "%{http_code}" https://$DOMAIN | grep -q "200\|302\|307"; then
        log "✅ n8n UI is accessible through Caddy"
        break
    fi
    sleep 2
done

# Provide helpful message about SSL warnings
echo ""
if [[ "$DOMAIN" == *.local ]] || [[ "$DOMAIN" == *localhost* ]]; then
    log "ℹ️  SSL Note: Since you're using a local domain ($DOMAIN),"
    log "   browsers will show a security warning. This is normal."
    log "   Just click 'Advanced' → 'Proceed to site' or 'Accept Risk'"
fi
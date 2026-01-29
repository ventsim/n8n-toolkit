#!/usr/bin/env bash
set -e
KEEP="${1:-14}"
[[ "$KEEP" =~ ^[0-9]+$ ]] || exit 0

ts=$(date +%Y%m%d_%H%M%S)
mkdir -p backups
tar -czf backups/n8n-$ts.tar.gz data/n8n .env

[ "$KEEP" -gt 0 ] && ls -1t backups/n8n-*.tar.gz | tail -n +$((KEEP+1)) | xargs -r rm

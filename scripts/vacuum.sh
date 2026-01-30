#!/usr/bin/env bash
docker compose exec -T n8n sqlite3 /home/node/.n8n/database.sqlite "VACUUM;"

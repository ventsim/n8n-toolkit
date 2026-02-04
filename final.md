# ✅ n8n Deployment Complete

Your automation platform is ready!

---

## 🔗 Access URLs

Primary Domain: `https://{{DOMAIN}}`

Local Alias:  `https://localhost.n8n`

Direct Access:  `http://localhost:{{PORT}}`

---

## ⚙️ Management Commands

```bash
# View logs
docker compose logs -f n8n
docker compose logs -f caddy

# Check status
docker compose ps

# Restart services
docker compose restart n8n
docker compose restart caddy

# Stop everything
docker compose down

# Update n8n
docker compose pull n8n
docker compose up -d

# Remove the entire stack
docker compose down
cd ~ && sudo rm -rf n8n-toolkit
```

## 🔐 Important Files

.env — Configuration

secrets/encryption_key.txt — Encryption key *(Ideally store a secure copy out  the host.)

Caddyfile — Reverse proxy config

## ⚠️ Troubleshooting

Check firewall:
```bash
sudo ufw allow 80,443
```
Verify /etc/hosts

Check logs:
```bash
docker compose logs
```
## 🔒 SSL Note

If you use localhost.n8n, your browser will warn about a self-signed cert.
This is normal. Click Advanced → Proceed.
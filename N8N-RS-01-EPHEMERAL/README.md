# n8n Stage 1 – Lean Prototyping Stack

This repository provides the **Stage 1 deployment pattern** for n8n: a lean, fast, and low-friction environment designed for **experimentation, prototyping, and early validation** of automation workflows.

It is intentionally minimal:
- Single node  
- No external databases  
- No Redis / queue mode  
- No backups / HA  
- No complex auth  
- No cloud dependencies

Just n8n + HTTPS + persistence — the fastest way to start shipping automations.

---

## 🎯 Purpose of This Stage

Use **Stage 1** when you want to:

- Prototype automation ideas  
- Validate business value of workflows  
- Build internal tools fast  
- Run experiments for 1–5 users  
- Avoid infrastructure overhead  

This is **not** intended for:
- Mission-critical workflows  
- Large teams  
- Long-term production data  
- High availability  
- Regulated environments  

For that → upgrade to **Stage 2+**

---

## 🧰 Tooling & Components

This stack deploys:

| Component | Purpose |
|----------|--------|
| **n8n** | Automation & workflow engine |
| **Docker** | Container runtime |
| **Docker Compose** | Single-node orchestration |
| **Caddy** | Reverse proxy + HTTPS (Let’s Encrypt or local CA) |
| **SQLite** | Embedded DB for fast startup |
| **Bash setup script** | Idempotent, interactive deployment |

---

## 🏗️ High-Level Architecture

             Internet / Local Network
                       │
                       ▼
             ┌────────────────────┐
             │        Caddy       │
             │  HTTPS + Reverse   │
             │      Proxy         │
             └────────┬───────────┘
                      │
                      ▼
             ┌────────────────────┐
             │        n8n         │
             │  Automation Engine │
             │   (SQLite + FS)    │
             └────────┬───────────┘
                      │
                      ▼
             ┌────────────────────┐
             │   Persistent Data   │
             │  (Docker Volumes)   │
             └────────────────────┘

---

## 🚀 Quickstart

### 1️⃣ Requirements

- Linux server / VM / home lab  
- 2GB RAM minimum 
- Ports 80 & 443 open (if using public domain)  

---

### 2️⃣ Clone & Run Setup

```bash
git clone https://github.com/your-org/n8n-stage1.git
cd n8n-stage1
chmod +x setup.sh
./setup.sh
```

The script will:

- Detect latest stable n8n version
- Ask for your domain / IP
- Generate encryption key
- Generate docker-compose.yml + Caddyfile
- Validate DNS (if using public domain)
- Prepare everything safely & idempotently

### 3️⃣ Start Services
docker compose up -d

### 4️⃣ Open n8n

➡ In your browser:

https://your-domain-or-ip


You’ll be guided through the n8n UI onboarding:
- Create admin user
- Configure credentials
- Start building workflows

## 🔐 Security Notes

- n8n requires HTTPS — handled by Caddy
- Your encryption key is generated and saved in:

secrets/encryption_key.txt


- Losing this key means:
❌ No credential recovery
❌ No safe migration
❌ No restore from backups

➡ Store it securely outside the server too.

## ⚙️ When to Upgrade (Decision Matrix)
| Need | Stage 1 | Stage 2+ |
| Backups | ❌ | ✅ |
| External DB (Postgres) | ❌ | ✅ |
| Redis / Queue Mode | ❌ | ✅ |
| High Availability | ❌	✅ |
| Large Team | ❌ | ✅ |
| Compliance | ❌ | ✅ |
| S3 Binary Storage | ❌ | ✅ |
| SSO / LDAP / SAML | ❌ | ✅ |

## ⬆️ Upgrade Path

When you outgrow Stage 1, move to:

👉 Stage 2 – Single Node Production Stack
Includes:
- PostgreSQL
- Redis
- Backups
- Duplicati
- Cron jobs
- Better observability

🔗 Stage 2 Repo:
https://github.com/your-org/n8n-stage2 (replace later)

## 🧠 Philosophy

Stage 1 is about speed and clarity:

- Ship fast
- Learn fast
- Validate fast
- Upgrade only when necessary

This repo is intentionally opinionated and minimal — no premature complexity.

Happy automating 🚀
# n8n Stage 1 – Lean Prototyping Stack

This repository provides the **Stage 1 deployment pattern** for n8n: a lean, fast, and low-friction environment designed for **experimentation, prototyping, proof of concept and early validation** of automation workflows.

## 🧠 Philosophy behind this deployment pattern 
• Speed
• Simplicity
• Learning fast

It is intentionally minimal:
- Single node (Isolation at Docker container level)
- No external databases
- No Redis / queue mode
- No backups / HA
- No cloud dependencies
- No tedious security measures

Just **n8n + HTTPS + persistence** — the fastest way to start making automations and testing integrating AI into your workflows.

---
## 👥 Who Is This For?

This stack is designed for:

• Solo developers & founders  
• Automation consultants  
• Startup teams validating internal tools  
• Product teams prototyping workflows  
• Hackathon & PoC environments  

If you want to:
✔ Prototype automation ideas  
✔ Validate workflows quickly   
✔ Run experiments for 1–5 users  
✔ Avoid infrastructure overhead  

→ This is for you.

Not intended for:
• Mission-critical workloads  
• Large teams  
• Compliance / HA / backups  

For that → **Stage 2+**
---

## 🧰 Components

| Component | Purpose |
|----------|--------|
| n8n | Automation engine |
| Docker | Container runtime |
| Docker Compose | Single-node orchestration |
| Caddy | Reverse proxy + HTTPS |
| SQLite | Embedded DB |
| Bash Setup | Idempotent installer |---
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

### Requirements
• Linux VM / server / lab  
• 2GB RAM minimum  
• Ports 80 & 443 open (public domains)

### Install

```bash
git clone https://github.com/n8n-toolkit.git
cd n8n-toolkit
chmod +x setup.sh
./setup.sh
# /setup.sh --interactive
```
The installer will:

• Detect latest n8n version
• Ask for domain / hostname
• Generate secrets
• Create configs
• Start containers

## 🔐 Security Notes

Your encryption key is stored in:
secrets/encryption_key.txt

Losing it means:
❌ No credential recovery
❌ No safe migration

➡ Back it up securely.

⬆️ Upgrade Path

## When you outgrow Stage 1:

👉 Stage 2 – Single Node Production Stack
Includes:
• PostgreSQL
• Backups
• Observability
• Better security
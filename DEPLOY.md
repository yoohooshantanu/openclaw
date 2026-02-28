# Deploying OpenClaw Bot Employee — Complete Guide

> End-to-end guide to deploy the bot on a GCP Compute Engine instance.
> You'll go from a blank VM to a working bot employee in Discord.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  GCP Compute Engine (e2-medium recommended)          │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  OpenClaw Gateway (Node.js daemon)             │  │
│  │  Port 18789 — Dashboard / WebChat              │  │
│  │                                                │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐    │  │
│  │  │ Triage 📋 │  │ Coder ⚡  │  │ Debugger🔍│   │  │
│  │  └──────────┘  └──────────┘  └──────────┘    │  │
│  │  ┌──────────┐  ┌──────────┐                   │  │
│  │  │Security🛡️│  │ Tester 🧪│                   │  │
│  │  └──────────┘  └──────────┘                   │  │
│  └────────────────────────────────────────────────┘  │
│                       ↕                              │
│  Discord Bot API    GitHub CLI    Sentry/Linear API  │
└──────────────────────────────────────────────────────┘
         ↕                               ↕
  Discord Servers                  Supabase (pgvector)
  (Multi-Guild)                    Memory + Durability
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Azure VM** | D2as_v5 (2 vCPU, 8GB RAM), Ubuntu 24.04, Central India |
| **Node.js 22+** | Required by OpenClaw |
| **GitHub Account** | Dedicated bot account with repo access |
| **Discord Bot** | Created at discord.com/developers |
| **API Keys** | At least one LLM provider (Gemini, OpenAI, or Anthropic) |
| **Sentry** (optional) | Auth token + org slug |
| **Linear** (optional) | Personal API key |

---

## Step 1: Connect to Your Azure VM

Your VM is already created: `openclaw-bot` in resource group `openclaw-rg` (Central India).

```bash
# SSH into your VM (replace YOUR_VM_IP with the public IP from Azure Portal)
ssh -i ~/.ssh/openclaw-bot_key.pem azureuser@YOUR_VM_IP

# Or use Azure CLI
az ssh vm --resource-group openclaw-rg --name openclaw-bot
```

> **Find your IP**: Azure Portal → openclaw-bot → Overview → Public IP address

### Open port 18789 for the dashboard (optional)
```bash
az vm open-port \
  --resource-group openclaw-rg \
  --name openclaw-bot \
  --port 18789 \
  --priority 1010
```

---

## Step 2: Install Dependencies on the VM

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# Verify
node --version   # Should be v22.x or higher
npm --version

# Install system tools
sudo apt install -y git curl jq docker.io

# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y
```

---

## Step 3: Install OpenClaw

```bash
# Official installer (recommended)
curl -fsSL https://openclaw.ai/install.sh | bash

# OR install via npm
npm install -g openclaw@latest

# Run the onboarding wizard
# This creates ~/.openclaw/ directory structure and installs the daemon
openclaw onboard --install-daemon

# Verify installation
openclaw --version
openclaw gateway status
```

After onboarding, your directory structure will be:
```
~/.openclaw/
├── openclaw.json       ← Main config (we'll replace this)
├── workspace/          ← Default workspace files
├── .env                ← Environment variables
└── state/              ← Internal state (auto-managed)
```

---

## Step 4: Set Up Environment Variables

```bash
# Create the .env file from our template
# (copy from your local repo, or create directly)
nano ~/.openclaw/.env
```

Paste the following and fill in real values:

```bash
# ── LLM Providers (at least one required) ────────────────
OPENAI_API_KEY=sk-your-openai-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key
# GEMINI_API_KEY=your-gemini-key

# ── GitHub (required for code tasks) ─────────────────────
GITHUB_TOKEN=ghp_your-github-personal-access-token

# ── Database (SQLite — no external service needed) ───────
# Stored locally, default: ~/.openclaw/bot.db
# OPENCLAW_DB_PATH=~/.openclaw/bot.db

# ── Discord (required) ──────────────────────────────────
DISCORD_BOT_TOKEN=your-discord-bot-token

# ── Sentry (optional — production error monitoring) ─────
# SENTRY_AUTH_TOKEN=your-sentry-auth-token
# SENTRY_ORG=your-sentry-org-slug

# ── Linear (optional — task management) ─────────────────
# LINEAR_API_KEY=lin_api_your-linear-key
```

### How to Get Each Key

| Key | Where to Get It |
|---|---|
| `OPENAI_API_KEY` | https://platform.openai.com/api-keys |
| `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys |
| `GITHUB_TOKEN` | GitHub → Settings → Developer settings → Personal access tokens → Fine-grained. Scopes: `repo`, `read:org`, `workflow` |
| `DISCORD_BOT_TOKEN` | https://discord.com/developers/applications → Bot → Reset Token |

| `SENTRY_AUTH_TOKEN` | Sentry → Settings → API Keys |
| `LINEAR_API_KEY` | Linear → Settings → API → Personal API keys |

---

## Step 5: Deploy the Database Schema

```bash
ssh user@YOUR_GCP_EXTERNAL_IP

# Create the SQLite database
sqlite3 ~/.openclaw/bot.db < schema.sql

# Verify tables were created
sqlite3 ~/.openclaw/bot.db ".tables"
# Expected: approvals  conversations  cost_tracking  tasks
```

This creates:

| Table / View | Purpose |
|---|---|
| `conversations` | Episodic memory (guild-scoped) |
| `tasks` | Execution durability (crash recovery) |
| `approvals` | Human-in-the-loop persistence |
| `cost_tracking` | Per-guild spend monitoring |
| `v_guild_spend` | 30-day spend summary view |
| `v_active_tasks` | Non-completed tasks view |
| `v_pending_approvals` | Pending approval queue view |

> **Important**: All tables have `guild_id` for multi-tenant isolation. No external database service needed.

---

## Step 6: Deploy Configuration Files

### Option A: Using the deploy script (from your local machine)

```bash
# Clone this config repo
git clone https://github.com/your-org/openclaw-config.git
cd openclaw-config

# Set the target
export OPENCLAW_HOST=user@YOUR_GCP_EXTERNAL_IP

# Deploy
./deploy.sh
```

### Option B: Manual SCP

```bash
# From your local machine
REMOTE=user@YOUR_GCP_EXTERNAL_IP

# Main config
scp gateway/openclaw.json $REMOTE:~/.openclaw/openclaw.json

# Workspace files (bot identity & behavior)
scp workspace/SOUL.md    $REMOTE:~/.openclaw/workspace/SOUL.md
scp workspace/AGENTS.md  $REMOTE:~/.openclaw/workspace/AGENTS.md
scp workspace/USER.md    $REMOTE:~/.openclaw/workspace/USER.md
scp workspace/MEMORY.md  $REMOTE:~/.openclaw/workspace/MEMORY.md

# Skills
scp -r skills/ $REMOTE:~/.openclaw/skills/
ssh $REMOTE "chmod +x ~/.openclaw/skills/**/*.sh"
```

### Option C: Docker Compose (alternative to Steps 2-6)

```bash
# On the GCP instance
git clone https://github.com/your-org/openclaw-config.git
cd openclaw-config
cp .env.example .env
nano .env  # Fill in real values
docker compose up -d
```

---

## Step 7: Authenticate GitHub CLI

```bash
ssh user@YOUR_GCP_EXTERNAL_IP

# Authenticate gh with your bot's token
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Verify
gh auth status
gh repo list --limit 5   # Should show accessible repos
```

---

## Step 8: Create Discord Bot

1. Go to https://discord.com/developers/applications
2. Click **New Application** → Name it "Claw" (or your preferred name)
3. Go to **Bot** section:
   - Click **Reset Token** → Copy the token → paste into `.env` as `DISCORD_BOT_TOKEN`
   - Enable **Message Content Intent** ✅
   - Enable **Server Members Intent** ✅
   - Enable **Presence Intent** ✅ (optional, for status)
4. Go to **OAuth2** → **URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Bot Permissions:
     - ✅ View Channels
     - ✅ Send Messages
     - ✅ Read Message History
     - ✅ Embed Links
     - ✅ Attach Files
     - ✅ Add Reactions
     - ✅ Create Public Threads
     - ✅ Send Messages in Threads
5. Copy the generated URL → Open in browser → Invite bot to your server
6. Enable **Developer Mode** in Discord (User Settings → Advanced → Developer Mode)

---

## Step 9: Pair Discord with OpenClaw

```bash
ssh user@YOUR_GCP_EXTERNAL_IP

# Enable Discord channel
openclaw config set channels.discord.enabled true --json

# Restart the gateway to pick up the new config
openclaw gateway restart

# The bot should now appear online in Discord
# DM the bot — it will show a pairing code
# Approve it:
openclaw pairing list discord
openclaw pairing approve discord <CODE>
```

---

## Step 10: Create Agent Workspaces

```bash
# Create a workspace for each agent
openclaw agents add triage
openclaw agents add coder
openclaw agents add debugger
openclaw agents add security
openclaw agents add tester

# Verify
openclaw agents list --bindings
```

---

## Step 11: Start the Gateway (Production)

```bash
# Start as a daemon (persists across reboots)
openclaw gateway --daemon

# Verify everything
openclaw gateway status
openclaw channels status --probe
openclaw health
```

**Dashboard**: Open `http://YOUR_GCP_IP:18789` in your browser.

---

## Step 12: Test the Bot

### Test 1: Ping
In Discord, mention the bot:
```
@claw What repos do you have access to?
```
✅ Expected: Bot reacts with ⚡, then lists accessible GitHub repos.

### Test 2: Full Code Fix Pipeline
```
@claw Fix the null pointer exception in auth.go in repo my-org/my-app
```
✅ Expected: Triage → Coder → Security review → Tester → CI → PR created.

### Test 3: PR Review (CodeRabbit-style)
```
@claw Review PR #42 on my-org/my-app
```
✅ Expected: Bot fetches diff, posts inline bug comments, approves or requests changes.

### Test 4: Sentry → Linear Bridge
```
@claw Check Sentry for errors on my-api and create tickets
```
✅ Expected: Bot lists Sentry errors, auto-creates Linear tickets for each.

### Test 5: Memory Isolation
In **Guild A**:
```
@claw Remember we use gRPC for all internal services
```
In **Guild B**:
```
@claw What communication protocol do we use internally?
```
✅ Expected: Guild B should NOT know about Guild A's gRPC preference.

### Test 6: Standup
```
@claw Give me your morning standup
```
✅ Expected: Bot checks Sentry errors, Linear tickets, open PR CI status.

### Test 7: Cost Check
```
@claw How much have we spent this month?
```
✅ Expected: Bot queries `get_guild_spend()` and reports per-model breakdown.

---

## Monitoring & Maintenance

### View Logs
```bash
openclaw logs --follow              # Live logs
openclaw logs --level error         # Errors only
```

### Update OpenClaw
```bash
npm update -g openclaw@latest
openclaw gateway restart
```

### Update Config (hot-reload, no restart needed)
```bash
# Edit config
nano ~/.openclaw/openclaw.json

# Reload without restart
openclaw config reload
```

### Health Check
```bash
openclaw health        # Quick check
openclaw doctor        # Full diagnostics
openclaw doctor --fix  # Auto-fix issues
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Bot doesn't come online | `openclaw gateway status` + check `DISCORD_BOT_TOKEN` |
| Bot doesn't respond to @mention | Check `groupPolicy` is `open` and Message Content Intent is enabled |
| "Config validation failed" | Run `openclaw doctor --fix` |
| Memory search not working | Verify `OPENAI_API_KEY` is set (needed for embeddings) |
| GitHub commands fail | `gh auth status` — re-auth if expired |
| Sentry/Linear scripts fail | Check tokens in `.env`, test with `./skills/sentry/sentry.sh projects` |
| Agent not routing | `openclaw agents list --bindings` — ensure triage is bound to discord |
| High costs | Check `cost_tracking` table in Supabase, adjust `agents.defaults.model` |
| Bot crashes mid-task | Restart gateway — check `tasks` table for PENDING tasks with retry info |
| Dashboard not accessible | Check firewall rule for port 18789, or use `openclaw dashboard` locally |

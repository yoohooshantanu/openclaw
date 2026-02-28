# OpenClaw Bot Employee — Config Repo

This repo is the **version-controlled source of truth** for your OpenClaw instance running on GCP. It contains configuration, workspace identity files, and database schemas that get deployed to `~/.openclaw/` on the target machine.

## Structure

```
├── gateway/
│   └── openclaw.json       → deploys to ~/.openclaw/openclaw.json
├── workspace/
│   ├── SOUL.md             → deploys to ~/.openclaw/workspace/SOUL.md
│   ├── AGENTS.md           → deploys to ~/.openclaw/workspace/AGENTS.md
│   ├── USER.md             → deploys to ~/.openclaw/workspace/USER.md
│   └── MEMORY.md           → deploys to ~/.openclaw/workspace/MEMORY.md
├── schema.sql              → run in Supabase SQL Editor
├── deploy.sh               → one-command deploy to GCP
├── .env.example            → environment variable template
└── DEPLOY.md               → full deployment guide
```

## Quick Deploy

```bash
# Set your GCP instance
export OPENCLAW_HOST=your-gcp-instance

# Deploy all config files
./deploy.sh
```

## Editing Workflow

1. Edit files in this repo (e.g., change a worker model in `gateway/openclaw.json`)
2. Commit to Git for version control
3. Run `./deploy.sh` to push changes to the GCP instance
4. OpenClaw hot-reloads most config changes automatically

See [DEPLOY.md](DEPLOY.md) for the full setup guide.

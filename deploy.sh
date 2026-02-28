#!/bin/bash
# OpenClaw Bot Employee — Deploy Script
# Syncs config files from this repo to your GCP OpenClaw instance
#
# Usage:
#   export OPENCLAW_HOST=user@your-gcp-instance
#   ./deploy.sh

set -euo pipefail

if [ -z "${OPENCLAW_HOST:-}" ]; then
  echo "Error: Set OPENCLAW_HOST first."
  echo "  export OPENCLAW_HOST=user@your-gcp-instance"
  exit 1
fi

REMOTE_BASE="~/.openclaw"

echo "═══ Deploying OpenClaw Config to ${OPENCLAW_HOST} ═══"
echo ""

# 1. Gateway config
echo "→ gateway/openclaw.json"
scp gateway/openclaw.json "${OPENCLAW_HOST}:${REMOTE_BASE}/openclaw.json"

# 2. Workspace files
echo "→ workspace/ (SOUL.md, AGENTS.md, USER.md, MEMORY.md)"
ssh "${OPENCLAW_HOST}" "mkdir -p ${REMOTE_BASE}/workspace"
scp workspace/SOUL.md   "${OPENCLAW_HOST}:${REMOTE_BASE}/workspace/SOUL.md"
scp workspace/AGENTS.md "${OPENCLAW_HOST}:${REMOTE_BASE}/workspace/AGENTS.md"
scp workspace/USER.md   "${OPENCLAW_HOST}:${REMOTE_BASE}/workspace/USER.md"
scp workspace/MEMORY.md "${OPENCLAW_HOST}:${REMOTE_BASE}/workspace/MEMORY.md"

# 3. Skills
echo "→ skills/ (github, sentry, linear, standup, bridge)"
ssh "${OPENCLAW_HOST}" "mkdir -p ${REMOTE_BASE}/skills"
scp -r skills/* "${OPENCLAW_HOST}:${REMOTE_BASE}/skills/"
ssh "${OPENCLAW_HOST}" "chmod +x ${REMOTE_BASE}/skills/**/*.sh 2>/dev/null || true"

# 4. Trigger hot-reload
echo ""
echo "→ Reloading config..."
ssh "${OPENCLAW_HOST}" "openclaw config reload 2>/dev/null || echo '   Gateway not running — config will apply on next start.'"

echo ""
echo "═══ Deploy complete! ═══"
echo ""
echo "Verify: ssh ${OPENCLAW_HOST} 'openclaw health'"
echo "Start:  ssh ${OPENCLAW_HOST} 'openclaw gateway --daemon'"

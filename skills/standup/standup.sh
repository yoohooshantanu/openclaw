#!/bin/bash
# ══════════════════════════════════════════════════════════
# Morning Standup Skill
# ══════════════════════════════════════════════════════════
# Checks Sentry for unresolved errors + Linear for assigned tasks
# Outputs a formatted standup message for the current guild
#
# Usage: ./standup.sh [project_slug]
# Designed to be triggered by OpenClaw's cron tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-}"

echo "☀️ **Good morning! Here's my status:**"
echo ""

# ── Sentry: Check for unresolved errors ──────────────────
echo "🔍 **Production Errors (Sentry)**"
if [ -n "$PROJECT" ]; then
  SENTRY_OUTPUT=$("$SCRIPT_DIR/../sentry/sentry.sh" issues "$PROJECT" 2>/dev/null || echo "")
else
  # Try to list projects and check the first one
  SENTRY_OUTPUT=$("$SCRIPT_DIR/../sentry/sentry.sh" projects 2>/dev/null || echo "")
  if [ -n "$SENTRY_OUTPUT" ]; then
    echo "Projects found: $SENTRY_OUTPUT"
    echo "(Pass project slug to get issues: ./standup.sh <project>)"
    SENTRY_OUTPUT=""
  fi
fi

if [ -n "$SENTRY_OUTPUT" ] && echo "$SENTRY_OUTPUT" | jq -e '.[0]' >/dev/null 2>&1; then
  echo "$SENTRY_OUTPUT" | jq -r '.[] | "🔴 \(.shortId // .id): \(.title) (×\(.count), \(.level))"' 2>/dev/null
else
  echo "✅ No unresolved errors"
fi
echo ""

# ── Linear: Check assigned tickets ──────────────────────
echo "📋 **My Tickets (Linear)**"
LINEAR_OUTPUT=$("$SCRIPT_DIR/../linear/linear.sh" my-tasks 2>/dev/null || echo "")

if [ -n "$LINEAR_OUTPUT" ] && echo "$LINEAR_OUTPUT" | jq -e '.[0]' >/dev/null 2>&1; then
  echo "$LINEAR_OUTPUT" | jq -r '.[] | {icon: (if .priority == "Urgent" then "🔴" elif .priority == "High" then "🟠" elif .priority == "Medium" then "🟡" else "🟢" end)} as $p | "\($p.icon) \(.identifier): \(.title) — \(.state)"' 2>/dev/null
else
  echo "📭 No assigned tickets"
fi
echo ""

# ── GitHub: Check for failing CI on recent PRs ──────────
echo "🏗️ **CI Status**"
GH_OUTPUT=$(gh pr list --author "@me" --state open --json number,title,statusCheckRollup --limit 5 2>/dev/null || echo "")
if [ -n "$GH_OUTPUT" ] && echo "$GH_OUTPUT" | jq -e '.[0]' >/dev/null 2>&1; then
  echo "$GH_OUTPUT" | jq -r '.[] | {status: (if (.statusCheckRollup // [] | map(select(.conclusion == "FAILURE")) | length) > 0 then "❌" else "✅" end)} as $s | "\($s.status) PR #\(.number): \(.title)"' 2>/dev/null
else
  echo "No open PRs"
fi
echo ""

echo "**Plan**: Working through tickets in priority order. Will post PR links as I go."

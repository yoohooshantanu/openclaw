#!/bin/bash
# ══════════════════════════════════════════════════════════
# Notify Skill — Proactive Monitoring & Alerts
# ══════════════════════════════════════════════════════════
# Checks for events that the bot should proactively report:
# - Sentry error spikes
# - CI failures on main branch
# - Stale tickets approaching due dates
#
# Usage: ./notify.sh <sentry_project> [gh_repo]
# Designed to run via OpenClaw's cron tool every 30 minutes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-}"
REPO="${2:-}"
ALERTS=""

# ── Sentry: Check for error spikes ──────────────────────
if [ -n "$PROJECT" ]; then
  STATS=$("$SCRIPT_DIR/../sentry/sentry.sh" stats "$PROJECT" 2>/dev/null || echo "")
  if [ -n "$STATS" ]; then
    RECENT=$(echo "$STATS" | jq -r '.recent_hour // 0')
    PEAK=$(echo "$STATS" | jq -r '.peak_hour // 0')
    TOTAL=$(echo "$STATS" | jq -r '.total // 0')

    # Alert if recent hour > 2x the average
    if [ "$TOTAL" -gt 0 ]; then
      AVG=$((TOTAL / 24))
      if [ "$RECENT" -gt $((AVG * 3)) ] && [ "$RECENT" -gt 10 ]; then
        ALERTS="${ALERTS}🚨 **Sentry spike detected!** ${RECENT} errors in the last hour (3x average of ${AVG}/hr) on \`${PROJECT}\`\n"
      fi
    fi
  fi
fi

# ── GitHub: Check CI on main branch ─────────────────────
if [ -n "$REPO" ]; then
  CI_STATUS=$(gh run list --repo "$REPO" --branch main --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo "")
  if [ "$CI_STATUS" = "failure" ]; then
    ALERTS="${ALERTS}❌ **CI failing on main** in \`${REPO}\`. Checking logs...\n"
  fi
fi

# ── Linear: Check approaching due dates ─────────────────
OVERDUE=$("$SCRIPT_DIR/../linear/linear.sh" my-tasks 2>/dev/null | jq -r '[.[]? | select(.due != "none" and .due != null)] | length' 2>/dev/null || echo "0")
if [ "$OVERDUE" -gt 0 ]; then
  ALERTS="${ALERTS}⏰ **${OVERDUE} tickets with due dates** need attention.\n"
fi

# ── Output ────────────────────────────────────────────────
if [ -n "$ALERTS" ]; then
  echo -e "🔔 **Proactive Alert**\n"
  echo -e "$ALERTS"
else
  # Silent if no alerts — don't spam the channel
  exit 0
fi

#!/bin/bash
# ══════════════════════════════════════════════════════════
# Sentry → Linear Bridge Skill
# ══════════════════════════════════════════════════════════
# Auto-creates Linear tickets from Sentry errors
# Prevents duplicates by checking if a ticket already exists
#
# Usage:
#   ./sentry-to-linear.sh <sentry_project> <linear_team_id> [priority]
#
# Priority: 1=urgent, 2=high, 3=medium (default), 4=low
# Set priority based on Sentry error level:
#   fatal/error → 2 (high), warning → 3 (medium), info → 4 (low)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT="${1:?Usage: sentry-to-linear.sh <sentry_project> <linear_team_id> [priority]}"
TEAM_ID="${2:?linear_team_id required}"
DEFAULT_PRIORITY="${3:-3}"

echo "🔗 Bridging Sentry ($PROJECT) → Linear..."
echo ""

# Fetch unresolved Sentry issues
ISSUES=$("$SCRIPT_DIR/../sentry/sentry.sh" issues "$PROJECT" "is:unresolved" 2>/dev/null || echo "[]")

if ! echo "$ISSUES" | jq -e '.[0]' >/dev/null 2>&1; then
  echo "✅ No unresolved Sentry issues. Nothing to bridge."
  exit 0
fi

# Process each Sentry issue
echo "$ISSUES" | jq -c '.[]' | while read -r ISSUE; do
  TITLE=$(echo "$ISSUE" | jq -r '.title')
  SHORT_ID=$(echo "$ISSUE" | jq -r '.shortId // "unknown"')
  LEVEL=$(echo "$ISSUE" | jq -r '.level // "error"')
  COUNT=$(echo "$ISSUE" | jq -r '.count // 0')
  CULPRIT=$(echo "$ISSUE" | jq -r '.culprit // "unknown"')
  PERMALINK=$(echo "$ISSUE" | jq -r '.permalink // ""')
  SENTRY_ID=$(echo "$ISSUE" | jq -r '.id')

  # Set priority based on error level
  case "$LEVEL" in
    fatal) PRIORITY=1 ;;
    error) PRIORITY=2 ;;
    warning) PRIORITY=3 ;;
    *) PRIORITY="$DEFAULT_PRIORITY" ;;
  esac

  # Check if Linear ticket already exists for this Sentry issue
  EXISTING=$("$SCRIPT_DIR/../linear/linear.sh" search "$SHORT_ID" 2>/dev/null || echo "[]")
  if echo "$EXISTING" | jq -e '.[0]' >/dev/null 2>&1; then
    EXISTING_ID=$(echo "$EXISTING" | jq -r '.[0].id')
    echo "⏭️  $SHORT_ID already tracked as $EXISTING_ID — skipping"
    continue
  fi

  # Create Linear ticket
  DESC="**Sentry Error**: [$SHORT_ID]($PERMALINK)

**Level**: $LEVEL
**Occurrences**: $COUNT
**Culprit**: $CULPRIT

---
Auto-created by Claw from Sentry alert."

  RESULT=$("$SCRIPT_DIR/../linear/linear.sh" create "$TEAM_ID" "[$SHORT_ID] $TITLE" "$DESC" "$PRIORITY" 2>/dev/null || echo "{}")

  if echo "$RESULT" | jq -e '.issue.identifier' >/dev/null 2>&1; then
    TICKET_ID=$(echo "$RESULT" | jq -r '.issue.identifier')
    echo "✅ Created $TICKET_ID ← $SHORT_ID: $TITLE (priority: $PRIORITY)"
  else
    echo "❌ Failed to create ticket for $SHORT_ID: $TITLE"
  fi
done

echo ""
echo "🔗 Bridge complete."

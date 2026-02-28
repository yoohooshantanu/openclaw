#!/bin/bash
# ══════════════════════════════════════════════════════════
# Sentry Skill — Production Error Monitoring
# ══════════════════════════════════════════════════════════
# API: https://docs.sentry.io/api/
# Auth: Bearer token with event:read, event:write, project:read scopes
#
# Required env:
#   SENTRY_AUTH_TOKEN  — Auth token (Settings → API Keys)
#   SENTRY_ORG         — Organization slug
#
# Usage:
#   ./sentry.sh projects                              # List all projects
#   ./sentry.sh issues <project> [query]              # List issues (default: is:unresolved)
#   ./sentry.sh issues <project> "is:unresolved level:error"
#   ./sentry.sh detail <issue_id>                     # Full issue details
#   ./sentry.sh events <issue_id> [limit]             # Latest events with stack traces
#   ./sentry.sh latest <issue_id>                     # Latest event (most useful for debugging)
#   ./sentry.sh resolve <issue_id>                    # Mark issue as resolved
#   ./sentry.sh assign <issue_id> <email>             # Assign to team member
#   ./sentry.sh stats <project> [period]              # Error stats (24h, 14d)

set -euo pipefail

TOKEN="${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN not set}"
ORG="${SENTRY_ORG:?SENTRY_ORG not set}"
BASE="https://sentry.io/api/0"

api() {
  local method="${1}" endpoint="${2}"; shift 2
  curl -sf \
    -X "$method" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$@" \
    "$BASE$endpoint"
}

ACTION="${1:?Usage: sentry.sh <action> [args...]}"
shift

case "$ACTION" in

  # ── List all projects in the org ────────────────────────
  projects)
    api GET "/organizations/$ORG/projects/" | \
      jq -r '.[] | "\(.slug) — \(.platform // "unknown") (\(.status))"'
    ;;

  # ── List issues for a project ──────────────────────────
  # Default query: is:unresolved
  # Custom: ./sentry.sh issues my-project "is:unresolved level:error assigned:me"
  issues)
    PROJECT="${1:?project slug required}"
    QUERY="${2:-is:unresolved}"
    api GET "/projects/$ORG/$PROJECT/issues/?query=$(printf %s "$QUERY" | jq -sRr @uri)&statsPeriod=24h&limit=15" | \
      jq '[.[] | {
        id,
        shortId,
        title,
        level,
        count: (.count | tonumber),
        userCount,
        firstSeen,
        lastSeen,
        project: .project.slug,
        culprit,
        permalink
      }]'
    ;;

  # ── Get full issue details ─────────────────────────────
  detail)
    ISSUE_ID="${1:?issue_id required}"
    api GET "/issues/$ISSUE_ID/" | \
      jq '{
        id, shortId, title, level, status,
        count: (.count | tonumber),
        userCount,
        culprit,
        firstSeen, lastSeen,
        project: .project.slug,
        assignedTo: (.assignedTo // "unassigned"),
        permalink,
        metadata,
        tags: [.tags[]? | {key, value: .topValues[0]?.value}]
      }'
    ;;

  # ── List events for an issue (with stack traces) ───────
  events)
    ISSUE_ID="${1:?issue_id required}"
    LIMIT="${2:-3}"
    api GET "/issues/$ISSUE_ID/events/?limit=$LIMIT" | \
      jq '[.[] | {
        eventID,
        dateCreated,
        message: (.message // .title),
        tags: [.tags[]? | select(.key == "environment" or .key == "release" or .key == "server_name") | {(.key): .value}],
        entries: [.entries[]? | select(.type == "exception") | .data.values[]? | {
          type,
          value,
          stacktrace: [.stacktrace.frames[-3:]? | {
            filename,
            lineNo,
            function: .function,
            context: [.context[]? | .[1]]
          }]
        }]
      }]'
    ;;

  # ── Get the LATEST event (most useful for debugging) ───
  latest)
    ISSUE_ID="${1:?issue_id required}"
    api GET "/issues/$ISSUE_ID/events/latest/" | \
      jq '{
        eventID,
        dateCreated,
        message: (.message // .title),
        environment: (.contexts.runtime.name // "unknown"),
        release: .release.version,
        exception: [.entries[]? | select(.type == "exception") | .data.values[]? | {
          type,
          value,
          frames: [.stacktrace.frames[-5:]? | {
            file: .filename,
            line: .lineNo,
            col: .colNo,
            fn: .function,
            code: [.context[]? | .[1]]
          }]
        }],
        breadcrumbs: [.entries[]? | select(.type == "breadcrumbs") | .data.values[-5:]? | {
          category,
          message,
          timestamp
        }]
      }'
    ;;

  # ── Resolve an issue ───────────────────────────────────
  resolve)
    ISSUE_ID="${1:?issue_id required}"
    api PUT "/issues/$ISSUE_ID/" -d '{"status":"resolved"}' | \
      jq '{id, status, statusDetails}'
    ;;

  # ── Assign an issue ────────────────────────────────────
  assign)
    ISSUE_ID="${1:?issue_id required}"
    EMAIL="${2:?assignee email required}"
    api PUT "/issues/$ISSUE_ID/" -d "{\"assignedTo\":\"$EMAIL\"}" | \
      jq '{id, assignedTo}'
    ;;

  # ── Project error stats ────────────────────────────────
  stats)
    PROJECT="${1:?project slug required}"
    PERIOD="${2:-24h}"
    api GET "/projects/$ORG/$PROJECT/stats/?stat=received&resolution=1h&statsPeriod=$PERIOD" | \
      jq '{
        total: (. | map(.[1]) | add),
        data_points: length,
        recent_hour: .[-1][1],
        peak_hour: (. | max_by(.[1]) | .[1])
      }'
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo ""
    echo "Available commands:"
    echo "  projects                         List all projects"
    echo "  issues <project> [query]         List issues (default: is:unresolved)"
    echo "  detail <issue_id>                Full issue details"
    echo "  events <issue_id> [limit]        Events with stack traces"
    echo "  latest <issue_id>                Latest event (best for debugging)"
    echo "  resolve <issue_id>               Mark resolved"
    echo "  assign <issue_id> <email>        Assign to person"
    echo "  stats <project> [period]         Error stats (24h, 14d)"
    exit 1
    ;;
esac

#!/bin/bash
# ══════════════════════════════════════════════════════════
# Linear Skill — Issue & Project Management
# ══════════════════════════════════════════════════════════
# API: https://developers.linear.app/docs/graphql/working-with-the-graphql-api
# Auth: Personal API key or OAuth token
#
# Required env:
#   LINEAR_API_KEY — Personal API key (Settings → API → Personal API keys)
#
# Usage:
#   ./linear.sh me                                     # Current user info
#   ./linear.sh teams                                  # List all teams
#   ./linear.sh my-tasks                               # My assigned open issues
#   ./linear.sh team-tasks <team_key>                  # All open issues for a team
#   ./linear.sh search <query>                         # Search issues by text
#   ./linear.sh detail <issue_id>                      # Full issue details
#   ./linear.sh create <team_id> <title> [desc] [priority]  # Create issue
#   ./linear.sh update-status <issue_id> <state_id>    # Change issue state
#   ./linear.sh assign <issue_id> <user_id>            # Assign issue
#   ./linear.sh comment <issue_id> <body>              # Add comment
#   ./linear.sh labels <team_id>                       # List available labels
#   ./linear.sh states <team_id>                       # List workflow states

set -euo pipefail

TOKEN="${LINEAR_API_KEY:?LINEAR_API_KEY not set}"
ENDPOINT="https://api.linear.app/graphql"

gql() {
  local query="$1"
  curl -sf "$ENDPOINT" \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$query"
}

ACTION="${1:?Usage: linear.sh <action> [args...]}"
shift

case "$ACTION" in

  # ── Current user info ──────────────────────────────────
  me)
    gql '{"query":"{ viewer { id name email admin } }"}' | \
      jq '.data.viewer'
    ;;

  # ── List all teams ─────────────────────────────────────
  teams)
    gql '{"query":"{ teams { nodes { id key name issueCount } } }"}' | \
      jq '.data.teams.nodes[] | "\(.key) — \(.name) (\(.issueCount) issues)"'
    ;;

  # ── My assigned open issues (sorted by priority) ───────
  my-tasks)
    gql '{"query":"{ viewer { assignedIssues(filter: { state: { type: { nin: [\"completed\", \"canceled\"] } } }, orderBy: updatedAt) { nodes { id identifier title priority priorityLabel url state { name type } dueDate labels { nodes { name } } project { name } } } } }"}' | \
      jq '[.data.viewer.assignedIssues.nodes[] | {
        id,
        identifier,
        title,
        priority: .priorityLabel,
        state: .state.name,
        project: (.project.name // "—"),
        due: (.dueDate // "none"),
        labels: [.labels.nodes[].name],
        url
      }]'
    ;;

  # ── Team issues ────────────────────────────────────────
  team-tasks)
    TEAM_KEY="${1:?team key required (e.g. ENG)}"
    gql "{\"query\":\"{ teams(filter: { key: { eq: \\\"$TEAM_KEY\\\" } }) { nodes { issues(filter: { state: { type: { nin: [\\\"completed\\\", \\\"canceled\\\"] } } }, first: 25, orderBy: updatedAt) { nodes { identifier title priorityLabel state { name } assignee { name } url } } } } }\"}" | \
      jq '[.data.teams.nodes[0].issues.nodes[] | {
        id: .identifier,
        title,
        priority: .priorityLabel,
        state: .state.name,
        assignee: (.assignee.name // "unassigned"),
        url
      }]'
    ;;

  # ── Search issues by text ──────────────────────────────
  search)
    QUERY="${1:?search query required}"
    ESCAPED=$(echo "$QUERY" | sed 's/"/\\"/g')
    gql "{\"query\":\"{ searchIssues(term: \\\"$ESCAPED\\\", first: 10) { nodes { identifier title state { name } assignee { name } url } } }\"}" | \
      jq '[.data.searchIssues.nodes[] | {
        id: .identifier,
        title,
        state: .state.name,
        assignee: (.assignee.name // "unassigned"),
        url
      }]'
    ;;

  # ── Full issue details ─────────────────────────────────
  detail)
    ISSUE_ID="${1:?issue id required}"
    gql "{\"query\":\"{ issue(id: \\\"$ISSUE_ID\\\") { id identifier title description priorityLabel state { name type } assignee { name email } creator { name } project { name } labels { nodes { name } } comments { nodes { body user { name } createdAt } } createdAt updatedAt url } }\"}" | \
      jq '.data.issue | {
        identifier, title, description,
        priority: .priorityLabel,
        state: .state.name,
        assignee: (.assignee.name // "unassigned"),
        creator: .creator.name,
        project: (.project.name // "—"),
        labels: [.labels.nodes[].name],
        comments: [.comments.nodes[] | {by: .user.name, body: .body, at: .createdAt}],
        created: .createdAt,
        updated: .updatedAt,
        url
      }'
    ;;

  # ── Create issue ───────────────────────────────────────
  # Priority: 0=none, 1=urgent, 2=high, 3=medium, 4=low
  create)
    TEAM_ID="${1:?team_id required}"
    TITLE="${2:?title required}"
    DESC="${3:-Created by OpenClaw bot employee}"
    PRIORITY="${4:-3}"
    ESCAPED_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    ESCAPED_DESC=$(echo "$DESC" | sed 's/"/\\"/g')
    gql "{\"query\":\"mutation { issueCreate(input: { teamId: \\\"$TEAM_ID\\\", title: \\\"$ESCAPED_TITLE\\\", description: \\\"$ESCAPED_DESC\\\", priority: $PRIORITY }) { success issue { id identifier title url state { name } } } }\"}" | \
      jq '.data.issueCreate | { success, issue: .issue | {identifier, title, url, state: .state.name} }'
    ;;

  # ── Update issue state (e.g., In Progress, Done) ──────
  update-status)
    ISSUE_ID="${1:?issue_id required}"
    STATE_ID="${2:?state_id required (use ./linear.sh states <team> to find IDs)}"
    gql "{\"query\":\"mutation { issueUpdate(id: \\\"$ISSUE_ID\\\", input: { stateId: \\\"$STATE_ID\\\" }) { success issue { identifier state { name } } } }\"}" | \
      jq '.data.issueUpdate'
    ;;

  # ── Assign issue ───────────────────────────────────────
  assign)
    ISSUE_ID="${1:?issue_id required}"
    USER_ID="${2:?user_id required}"
    gql "{\"query\":\"mutation { issueUpdate(id: \\\"$ISSUE_ID\\\", input: { assigneeId: \\\"$USER_ID\\\" }) { success issue { identifier assignee { name } } } }\"}" | \
      jq '.data.issueUpdate'
    ;;

  # ── Add comment to issue ───────────────────────────────
  comment)
    ISSUE_ID="${1:?issue_id required}"
    BODY="${2:?comment body required}"
    ESCAPED_BODY=$(echo "$BODY" | sed 's/"/\\"/g')
    gql "{\"query\":\"mutation { commentCreate(input: { issueId: \\\"$ISSUE_ID\\\", body: \\\"$ESCAPED_BODY\\\" }) { success comment { id body } } }\"}" | \
      jq '.data.commentCreate'
    ;;

  # ── List workflow states for a team ────────────────────
  states)
    TEAM_ID="${1:?team_id required}"
    gql "{\"query\":\"{ workflowStates(filter: { team: { id: { eq: \\\"$TEAM_ID\\\" } } }) { nodes { id name type position } } }\"}" | \
      jq '[.data.workflowStates.nodes | sort_by(.position)[] | {id, name, type}]'
    ;;

  # ── List labels for a team ─────────────────────────────
  labels)
    TEAM_ID="${1:?team_id required}"
    gql "{\"query\":\"{ issueLabels(filter: { team: { id: { eq: \\\"$TEAM_ID\\\" } } }) { nodes { id name color } } }\"}" | \
      jq '[.data.issueLabels.nodes[] | {id, name, color}]'
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo ""
    echo "Available commands:"
    echo "  me                                   Current user info"
    echo "  teams                                List all teams"
    echo "  my-tasks                             My assigned open issues"
    echo "  team-tasks <team_key>                Team's open issues"
    echo "  search <query>                       Search issues"
    echo "  detail <issue_id>                    Full issue details"
    echo "  create <team_id> <title> [desc] [priority]"
    echo "  update-status <issue_id> <state_id>  Change issue state"
    echo "  assign <issue_id> <user_id>          Assign issue"
    echo "  comment <issue_id> <body>            Add comment"
    echo "  states <team_id>                     List workflow states"
    echo "  labels <team_id>                     List labels"
    exit 1
    ;;
esac

#!/bin/bash
# ══════════════════════════════════════════════════════════
# PR Review Skill — CodeRabbit-Style Automated Code Review
# ══════════════════════════════════════════════════════════
# Fetches a PR diff, prepares it for LLM-based review,
# and can post review comments back to GitHub.
#
# Usage:
#   ./pr-review.sh fetch <repo> <pr_number>       # Fetch PR diff + metadata for review
#   ./pr-review.sh comment <repo> <pr_number> <body>  # Post a review comment
#   ./pr-review.sh approve <repo> <pr_number>     # Approve the PR
#   ./pr-review.sh request-changes <repo> <pr_number> <body>  # Request changes
#   ./pr-review.sh inline <repo> <pr_number> <file> <line> <comment>  # Inline comment
#   ./pr-review.sh watch <repo> [interval_min]    # Poll for new PRs to review

set -euo pipefail

ACTION="${1:?Usage: pr-review.sh <action> [args...]}"
shift

case "$ACTION" in

  # ── Fetch PR for review ────────────────────────────────
  # Returns structured data the LLM can analyze
  fetch)
    REPO="${1:?repo required (owner/name)}"
    PR="${2:?pr_number required}"

    echo "═══ PR #$PR Review Package ═══"
    echo ""

    # PR metadata
    echo "## Metadata"
    gh pr view "$PR" --repo "$REPO" --json title,body,author,headRefName,baseRefName,additions,deletions,changedFiles,labels,reviewDecision,commits \
      --jq '{
        title,
        author: .author.login,
        branch: "\(.headRefName) → \(.baseRefName)",
        changes: "\(.additions)+ \(.deletions)- across \(.changedFiles) files",
        labels: [.labels[].name],
        reviewStatus: (.reviewDecision // "PENDING"),
        commitCount: (.commits | length)
      }'
    echo ""

    # Changed files list
    echo "## Changed Files"
    gh pr diff "$PR" --repo "$REPO" --name-only
    echo ""

    # Full diff (capped at 800 lines for context window)
    echo "## Diff"
    gh pr diff "$PR" --repo "$REPO" | head -800
    TOTAL_LINES=$(gh pr diff "$PR" --repo "$REPO" | wc -l)
    if [ "$TOTAL_LINES" -gt 800 ]; then
      echo ""
      echo "... (diff truncated, $TOTAL_LINES total lines, showing first 800)"
    fi
    echo ""

    # Existing review comments
    echo "## Existing Reviews"
    gh pr view "$PR" --repo "$REPO" --json reviews --jq '.reviews[] | "\(.author.login): \(.state) — \(.body[:200])"' 2>/dev/null || echo "No reviews yet"
    echo ""

    echo "═══ Review Checklist ═══"
    echo "Analyze the diff above for:"
    echo "1. 🐛 Bugs — null pointers, off-by-one, race conditions, unhandled errors"
    echo "2. 🔒 Security — injection, auth bypass, secret exposure, unsafe deserialization"
    echo "3. ⚡ Performance — N+1 queries, unbounded loops, missing indexes, memory leaks"
    echo "4. 🧪 Testing — missing test coverage for new code paths"
    echo "5. 📐 Design — naming, abstractions, code duplication, API contract changes"
    echo "6. 💥 Breaking — backward-incompatible changes, API/schema migrations"
    ;;

  # ── Post a general review comment ──────────────────────
  comment)
    REPO="${1:?repo required}"
    PR="${2:?pr_number required}"
    BODY="${3:?comment body required}"
    gh pr review "$PR" --repo "$REPO" --comment --body "$BODY"
    echo "✅ Review comment posted on PR #$PR"
    ;;

  # ── Approve the PR ─────────────────────────────────────
  approve)
    REPO="${1:?repo required}"
    PR="${2:?pr_number required}"
    BODY="${3:-LGTM! Reviewed by Claw 🤖}"
    gh pr review "$PR" --repo "$REPO" --approve --body "$BODY"
    echo "✅ PR #$PR approved"
    ;;

  # ── Request changes ────────────────────────────────────
  request-changes)
    REPO="${1:?repo required}"
    PR="${2:?pr_number required}"
    BODY="${3:?review body required}"
    gh pr review "$PR" --repo "$REPO" --request-changes --body "$BODY"
    echo "🔄 Changes requested on PR #$PR"
    ;;

  # ── Inline comment on specific file + line ─────────────
  inline)
    REPO="${1:?repo required}"
    PR="${2:?pr_number required}"
    FILE="${3:?file path required}"
    LINE="${4:?line number required}"
    COMMENT="${5:?comment text required}"
    # Use gh api to post a review comment on a specific line
    gh api "repos/$REPO/pulls/$PR/comments" \
      -f body="$COMMENT" \
      -f path="$FILE" \
      -F line="$LINE" \
      -f side="RIGHT" \
      --jq '{id, path, line: .line, body: .body}'
    echo "✅ Inline comment posted on $FILE:$LINE"
    ;;

  # ── Watch for new PRs and flag them for review ─────────
  watch)
    REPO="${1:?repo required}"
    INTERVAL="${2:-5}"

    echo "👁️ Watching $REPO for new PRs (every ${INTERVAL}min)..."

    # Get list of PRs that haven't been reviewed by us
    OPEN_PRS=$(gh pr list --repo "$REPO" --state open --json number,title,author,reviewDecision,labels \
      --jq '[.[] | select(.reviewDecision != "APPROVED" and .reviewDecision != "CHANGES_REQUESTED")]')

    if echo "$OPEN_PRS" | jq -e '.[0]' >/dev/null 2>&1; then
      echo ""
      echo "📋 PRs needing review:"
      echo "$OPEN_PRS" | jq -r '.[] | "  #\(.number) by \(.author.login): \(.title)"'
      echo ""
      echo "Run: ./pr-review.sh fetch $REPO <pr_number>"
    else
      echo "✅ All open PRs have been reviewed"
    fi
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo ""
    echo "Available commands:"
    echo "  fetch <repo> <pr#>                    Fetch PR diff + metadata for review"
    echo "  comment <repo> <pr#> <body>           Post review comment"
    echo "  approve <repo> <pr#>                  Approve PR"
    echo "  request-changes <repo> <pr#> <body>   Request changes"
    echo "  inline <repo> <pr#> <file> <line> <comment>  Inline comment"
    echo "  watch <repo>                          Find PRs needing review"
    exit 1
    ;;
esac

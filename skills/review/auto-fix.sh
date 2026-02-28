#!/bin/bash
# ══════════════════════════════════════════════════════════
# Auto-Fix Skill — Find bugs in PR and push fixes
# ══════════════════════════════════════════════════════════
# End-to-end pipeline: review PR → find bugs → fix → push
#
# Usage:
#   ./auto-fix.sh <repo> <pr_number> <workspace_dir>
#
# This script:
# 1. Checks out the PR branch
# 2. Fetches the diff for LLM review
# 3. The LLM (via OpenClaw) analyzes and fixes bugs
# 4. Runs tests to validate
# 5. Pushes fix commit to the PR branch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="${1:?repo required (owner/name)}"
PR="${2:?pr_number required}"
DIR="${3:?workspace_dir required}"

echo "═══ Auto-Fix Pipeline for PR #$PR ═══"
echo ""

# 1. Clone and checkout the PR branch
echo "→ Step 1: Checking out PR #$PR..."
if [ ! -d "$DIR/.git" ]; then
  gh repo clone "$REPO" "$DIR" -- --depth=50
fi
cd "$DIR"
gh pr checkout "$PR"
BRANCH=$(git branch --show-current)
echo "  On branch: $BRANCH"
echo ""

# 2. Fetch the diff
echo "→ Step 2: Fetching diff..."
DIFF=$(gh pr diff "$PR" --repo "$REPO")
FILE_COUNT=$(echo "$DIFF" | grep "^diff --git" | wc -l)
ADD_COUNT=$(echo "$DIFF" | grep "^+" | grep -v "^+++" | wc -l)
DEL_COUNT=$(echo "$DIFF" | grep "^-" | grep -v "^---" | wc -l)
echo "  $FILE_COUNT files changed, $ADD_COUNT additions, $DEL_COUNT deletions"
echo ""

# 3. Get changed file list
echo "→ Step 3: Changed files:"
CHANGED_FILES=$(gh pr diff "$PR" --repo "$REPO" --name-only)
echo "$CHANGED_FILES" | sed 's/^/  /'
echo ""

# 4. Output the review package for LLM analysis
echo "→ Step 4: Review package ready"
echo ""
echo "════════════════════════════════════════"
echo "FILES FOR REVIEW:"
echo "════════════════════════════════════════"

# Show each changed file's full content (so the LLM can fix it)
echo "$CHANGED_FILES" | while read -r FILE; do
  if [ -f "$FILE" ]; then
    LINES=$(wc -l < "$FILE")
    echo ""
    echo "──── $FILE ($LINES lines) ────"
    if [ "$LINES" -lt 300 ]; then
      cat "$FILE"
    else
      head -300 "$FILE"
      echo "... (truncated, $LINES lines total)"
    fi
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "DIFF:"
echo "════════════════════════════════════════"
echo "$DIFF" | head -500

echo ""
echo "════════════════════════════════════════"
echo "INSTRUCTIONS FOR LLM:"
echo "════════════════════════════════════════"
echo ""
echo "Review the above code and diff. For each bug found:"
echo "1. Describe the bug (what, where, severity)"
echo "2. Use 'edit' or 'apply_patch' to fix the file"
echo "3. After all fixes, run the test command below"
echo ""

# 5. Detect language and suggest test command
if [ -f "go.mod" ]; then
  echo "Test command: go test ./..."
elif [ -f "package.json" ]; then
  echo "Test command: npm test"
elif [ -f "Cargo.toml" ]; then
  echo "Test command: cargo test"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  echo "Test command: pytest"
else
  echo "Test command: (detect manually)"
fi

echo ""
echo "After fixes pass tests, commit with:"
echo "  git add -A && git commit -m 'fix: address review findings' && git push"

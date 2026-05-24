#!/usr/bin/env bash
# Parses a walkaway build plan markdown file and outputs KEY=VALUE pairs to stdout.
# Usage: source <(bash lib/parse-plan.sh <plan-file>)
# Outputs: FEATURE_NAME, BRANCH_NAME, REPO_PATH

set -euo pipefail

PLAN_FILE="${1:-}"

if [[ -z "$PLAN_FILE" ]]; then
  echo "Usage: parse-plan.sh <plan-file>" >&2
  exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Plan file not found: $PLAN_FILE" >&2
  exit 1
fi

# Extract value from a section: find "## <Section>" then grab the backtick-quoted value
# on the next non-blank line.
_extract_section_value() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 ~ "^## " section {found=1; next}
    found && /^##/ {exit}
    found && /`[^`]+`/ {
      s = $0
      # strip everything before first backtick
      sub(/^[^`]*`/, "", s)
      # strip everything from next backtick onward
      sub(/`.*/, "", s)
      if (s != "") { print s; exit }
    }
  ' "$file"
}

FEATURE_NAME=$(_extract_section_value "$PLAN_FILE" "Feature name")
BRANCH_NAME=$(_extract_section_value "$PLAN_FILE" "Branch name")

if [[ -z "$FEATURE_NAME" ]]; then
  echo "ERROR: Could not extract '## Feature name' from: $PLAN_FILE" >&2
  exit 1
fi

if [[ -z "$BRANCH_NAME" ]]; then
  echo "ERROR: Could not extract '## Branch name' from: $PLAN_FILE" >&2
  exit 1
fi

# Extract repo path from "## Repo" section (optional).
# Looks for a backtick-quoted value that starts with ~ or /.
REPO_PATH=$(awk '
  /^## Repo/{found=1; next}
  found && /^##/{exit}
  found && /`[~\/][^`]*`/{
    s = $0
    sub(/^[^`]*`/, "", s)
    sub(/`.*/, "", s)
    if (s != "") { print s; exit }
  }
' "$PLAN_FILE")

# Fallback: infer from plan file location (plan lives at <repo>/handoff/build-plan-*.md)
if [[ -z "$REPO_PATH" ]]; then
  REPO_PATH="$(cd "$(dirname "$PLAN_FILE")/.." && pwd)"
fi

# Expand leading ~ to $HOME
REPO_PATH="${REPO_PATH/#\~/$HOME}"
# Strip trailing slash
REPO_PATH="${REPO_PATH%/}"

echo "FEATURE_NAME=${FEATURE_NAME}"
echo "BRANCH_NAME=${BRANCH_NAME}"
echo "REPO_PATH=${REPO_PATH}"

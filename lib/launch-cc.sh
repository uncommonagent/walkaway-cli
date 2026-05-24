#!/usr/bin/env bash
# Renders the Block 2 template and launches CC in the target repo.
# Usage: source lib/launch-cc.sh; cc_launch <vars...>  OR  call directly.
#
# Required env:
#   FEATURE_NAME, BRANCH_NAME, REPO_PATH, BUILD_PLAN_PATH
# Optional env:
#   WALKAWAY_PROTOCOL_PATH (default: ~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md)
#   WALKAWAY_TEMPLATE      (default: <this-script-dir>/../templates/block-2-template.md)
#   DRY_RUN                (true = print prompt, don't exec)

set -euo pipefail

_LAUNCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_TEMPLATE_DEFAULT="${_LAUNCH_DIR}/../templates/block-2-template.md"
_PROTOCOL_DEFAULT="${HOME}/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md"

cc_launch() {
  local feature_name="${FEATURE_NAME}"
  local branch_name="${BRANCH_NAME}"
  local repo_path="${REPO_PATH}"
  local build_plan_path="${BUILD_PLAN_PATH}"
  local protocol_path="${WALKAWAY_PROTOCOL_PATH:-$_PROTOCOL_DEFAULT}"
  local template_file="${WALKAWAY_TEMPLATE:-$_TEMPLATE_DEFAULT}"
  local dry_run="${DRY_RUN:-false}"

  # Validate
  if [[ -z "$feature_name" || -z "$branch_name" || -z "$repo_path" || -z "$build_plan_path" ]]; then
    echo "ERROR: FEATURE_NAME, BRANCH_NAME, REPO_PATH, and BUILD_PLAN_PATH must all be set." >&2
    return 1
  fi

  if [[ ! -f "$template_file" ]]; then
    echo "ERROR: Block 2 template not found: $template_file" >&2
    return 1
  fi

  if [[ ! -f "$protocol_path" ]]; then
    echo "WARNING: WALKAWAY_PROTOCOL_PATH not found: $protocol_path" >&2
    echo "  Set WALKAWAY_PROTOCOL_PATH env var to the correct location." >&2
  fi

  if [[ ! -d "$repo_path" ]]; then
    echo "ERROR: REPO_PATH does not exist: $repo_path" >&2
    return 1
  fi

  # Render template using sed — no envsubst needed, pure bash/sed
  # Values are paths/names that should not contain sed delimiter |
  local rendered
  rendered=$(sed \
    -e "s|\${BUILD_PLAN_PATH}|${build_plan_path}|g" \
    -e "s|\${FEATURE_NAME}|${feature_name}|g" \
    -e "s|\${WALKAWAY_PROTOCOL_PATH}|${protocol_path}|g" \
    -e "s|\${REPO_PATH}|${repo_path}|g" \
    -e "s|\${BRANCH_NAME}|${branch_name}|g" \
    "$template_file")

  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "  [dry-run] would launch CC in: $repo_path"
    echo "  Prompt preview (first 300 chars):"
    echo "  -------------------------------------------------------"
    echo "$rendered" | head -c 300
    echo ""
    echo "  -------------------------------------------------------"
    return 0
  fi

  echo "Launching CC in $repo_path ..."
  echo "  Feature: $feature_name  Branch: $branch_name"
  echo ""

  # CC runs in foreground so Jim can see and interact with the session.
  cd "$repo_path" && exec claude --dangerously-skip-permissions "$rendered"
}

# If run directly (not sourced), execute immediately
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cc_launch "$@"
fi

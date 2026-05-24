#!/usr/bin/env bash
# walkaway — kick off a walkaway build from any terminal.
# Usage: walkaway [--worktree] [--dry-run] [--force] [--help] <build-plan-path>

set -euo pipefail

# Resolve symlinks so lib/ is found even when invoked via a symlink in PATH
_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$_SOURCE" ]]; do
  _DIR="$(cd -P "$(dirname "$_SOURCE")" && pwd)"
  _SOURCE="$(readlink "$_SOURCE")"
  [[ "$_SOURCE" != /* ]] && _SOURCE="$_DIR/$_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_SOURCE")" && pwd)"
unset _SOURCE _DIR

# shellcheck source=lib/parse-plan.sh
# shellcheck source=lib/watcher.sh
# shellcheck source=lib/launch-cc.sh
# shellcheck source=lib/worktree.sh
source "${SCRIPT_DIR}/lib/watcher.sh"
source "${SCRIPT_DIR}/lib/launch-cc.sh"
source "${SCRIPT_DIR}/lib/worktree.sh"

# ── help ──────────────────────────────────────────────────────────────────────
show_help() {
  cat <<'HELP'
walkaway — kick off a walkaway build session

USAGE
  walkaway [OPTIONS] <build-plan-path>

OPTIONS
  --worktree    Create a git worktree for a parallel build. Copies .env.local,
                runs install, opens VS Code, then launches CC there.
  --dry-run     Print what would happen without executing anything.
  --force       Skip the "another walkaway is running" safety check.
  --help, -h    Show this help.

ENVIRONMENT
  WALKAWAY_PROTOCOL_PATH   Override path to WALKAWAY_BUILD_PROTOCOL.md.
                           Default: ~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md
  NTFY_TOPIC               ntfy.sh topic for build notifications.
                           Default: jim-throughline-9k2x7q-builds

EXAMPLES
  # Solo build
  walkaway ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-4.md

  # Parallel build in a fresh worktree
  walkaway --worktree ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-k.md

  # Verify without executing
  walkaway --dry-run ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md

STATE & LOGS
  ~/.walkaway-cli/state/watcher-<feature>.json   Watcher PID + metadata
  ~/.walkaway-cli/logs/watcher-<feature>.log     Watcher output
  ~/.walkaway-cli/state/.watcher-state-<feature> Handoff dir snapshot (watcher internal)
HELP
}

# ── arg parsing ───────────────────────────────────────────────────────────────
PLAN_FILE=""
USE_WORKTREE=false
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)  USE_WORKTREE=true; shift ;;
    --dry-run)   DRY_RUN=true; shift ;;
    --force)     FORCE=true; shift ;;
    --help|-h)   show_help; exit 0 ;;
    -*)          echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    *)           PLAN_FILE="$1"; shift ;;
  esac
done

if [[ -z "$PLAN_FILE" ]]; then
  echo "ERROR: build-plan-path is required." >&2
  echo "" >&2
  show_help
  exit 1
fi

# Resolve to absolute path
PLAN_FILE="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: Build plan not found: $PLAN_FILE" >&2
  exit 1
fi

# ── parse plan ────────────────────────────────────────────────────────────────
echo "Parsing build plan: $PLAN_FILE"
eval "$(bash "${SCRIPT_DIR}/lib/parse-plan.sh" "$PLAN_FILE")"

export FEATURE_NAME BRANCH_NAME REPO_PATH BUILD_PLAN_PATH="$PLAN_FILE" DRY_RUN

echo "  Feature: $FEATURE_NAME"
echo "  Branch:  $BRANCH_NAME"
echo "  Repo:    $REPO_PATH"
echo ""

# ── collision check ───────────────────────────────────────────────────────────
if [[ "$FORCE" != "true" ]] && watcher_running "$FEATURE_NAME"; then
  echo "ERROR: A walkaway for '$FEATURE_NAME' is already running." >&2
  echo "  Use --force to start another session anyway." >&2
  exit 1
fi

# ── branch setup ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" != "true" ]]; then
  if ! git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
    echo "Creating branch $BRANCH_NAME in $REPO_PATH ..."
    git -C "$REPO_PATH" checkout -b "$BRANCH_NAME"
  else
    # Branch exists — ask before switching
    local_current=$(git -C "$REPO_PATH" branch --show-current)
    if [[ "$local_current" != "$BRANCH_NAME" ]]; then
      echo "Branch '$BRANCH_NAME' already exists. Switch to it? [y/N]"
      read -r answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        git -C "$REPO_PATH" checkout "$BRANCH_NAME"
      else
        echo "Aborted. Check out the branch manually and re-run." >&2
        exit 1
      fi
    fi
  fi
else
  echo "  [dry-run] would verify/create branch: $BRANCH_NAME in $REPO_PATH"
fi

# ── worktree (optional) ───────────────────────────────────────────────────────
if [[ "$USE_WORKTREE" == "true" ]]; then
  worktree_create
fi

# ── watcher startup ───────────────────────────────────────────────────────────
handoff_dir="${REPO_PATH}/handoff"
if [[ ! -d "$handoff_dir" && "$DRY_RUN" != "true" ]]; then
  mkdir -p "$handoff_dir"
fi
watcher_start "$handoff_dir" "$FEATURE_NAME" "$DRY_RUN"

# ── launch CC ────────────────────────────────────────────────────────────────
cc_launch

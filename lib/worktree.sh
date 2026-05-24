#!/usr/bin/env bash
# Creates a git worktree for parallel walkaway builds and prepares it.
# Source this file; call worktree_create.
#
# Required env: FEATURE_NAME, BRANCH_NAME, REPO_PATH
# Sets on success: REPO_PATH (updated to worktree path)

set -euo pipefail

worktree_create() {
  local feature_name="${FEATURE_NAME}"
  local branch_name="${BRANCH_NAME}"
  local source_repo="${REPO_PATH}"
  local dry_run="${DRY_RUN:-false}"

  local repo_basename
  repo_basename=$(basename "$source_repo")
  local worktree_path
  worktree_path="$(dirname "$source_repo")/${repo_basename}-${feature_name}"

  if [[ "$dry_run" == "true" ]]; then
    echo "  [dry-run] would create worktree:"
    echo "    source:   $source_repo"
    echo "    worktree: $worktree_path"
    echo "    branch:   $branch_name"
    echo "  [dry-run] would copy .env.local if present"
    echo "  [dry-run] would detect package manager and run install"
    echo "  [dry-run] would open VS Code at $worktree_path"
    return 0
  fi

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo "Worktree already exists at $worktree_path"
    echo "Continuing with existing worktree."
    export REPO_PATH="$worktree_path"
    return 0
  fi

  echo "Creating worktree at $worktree_path on branch $branch_name ..."

  # Create the worktree. If branch already exists locally, check it out directly.
  if git -C "$source_repo" show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    git -C "$source_repo" worktree add "$worktree_path" "$branch_name"
  else
    git -C "$source_repo" worktree add "$worktree_path" -b "$branch_name"
  fi

  # Copy .env.local if present
  if [[ -f "$source_repo/.env.local" ]]; then
    cp "$source_repo/.env.local" "$worktree_path/.env.local"
    echo "Copied .env.local to worktree."
  fi

  # Detect package manager
  local pm="npm"
  if [[ -f "$worktree_path/pnpm-lock.yaml" ]]; then
    pm="pnpm"
  elif [[ -f "$worktree_path/yarn.lock" ]]; then
    pm="yarn"
  elif [[ -f "$worktree_path/bun.lockb" ]]; then
    pm="bun"
  fi

  echo "Running $pm install in worktree ..."
  (cd "$worktree_path" && $pm install)

  # Open in VS Code
  if command -v code &>/dev/null; then
    echo "Opening VS Code at $worktree_path ..."
    code "$worktree_path"
  else
    echo "VS Code CLI not found — open $worktree_path manually."
  fi

  export REPO_PATH="$worktree_path"
  echo "Worktree ready at $worktree_path"
}

# Cleanup helper (for manual use after merge)
worktree_remove() {
  local feature_name="${1:-$FEATURE_NAME}"
  local source_repo="${2:-$REPO_PATH}"
  local repo_basename
  repo_basename=$(basename "$source_repo")
  local worktree_path
  worktree_path="$(dirname "$source_repo")/${repo_basename}-${feature_name}"

  if [[ ! -d "$worktree_path" ]]; then
    echo "No worktree found at $worktree_path"
    return 0
  fi

  git -C "$source_repo" worktree remove "$worktree_path" --force
  echo "Worktree removed: $worktree_path"
}

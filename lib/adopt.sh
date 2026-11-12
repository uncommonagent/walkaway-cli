#!/usr/bin/env bash
# Registry backfill: adopt walkaway builds that were launched before the registry existed.
#
# Source of truth is the walkaway launch log (`nohup walkaway <plan> > /tmp/walkaway-<feature>[-N].log`):
# it records the plan, feature, branch, repo and the watcher PID. walkaway execs the builder in its own
# process and the watcher is its child, so builder PID = PPID of the logged watcher PID. No process-name
# matching. A log whose watcher is gone (fired, killed) cannot be adopted and is skipped.
#
#   adopt.sh [log-glob]   default glob: /tmp/walkaway-*.log

set -uo pipefail

ADOPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/registry.sh
source "${ADOPT_DIR}/registry.sh"

WALKAWAY_LAUNCH_LOG_GLOB="${1:-${WALKAWAY_LAUNCH_LOG_GLOB:-/tmp/walkaway-*.log}}"

_lstart_epoch() { date -j -f '%a %b %d %T %Y' "$1" +%s 2>/dev/null; }

adopt_all() {
  local log adopted=0 skipped=0
  # Newest logs first so a feature's latest launch wins.
  # shellcheck disable=SC2086  # the glob must expand
  for log in $(ls -t $WALKAWAY_LAUNCH_LOG_GLOB 2>/dev/null); do
    local plan feature branch repo wpid worktree_path
    plan=$(sed -n 's/^Parsing build plan: //p' "$log" | head -1)
    feature=$(sed -n 's/^  Feature: *//p' "$log" | head -1)
    branch=$(sed -n 's/^  Branch: *//p' "$log" | head -1)
    repo=$(sed -n 's/^  Repo: *//p' "$log" | head -1)
    wpid=$(sed -n 's/^Watcher started (PID \([0-9]*\)).*/\1/p' "$log" | tail -1)
    worktree_path=$(sed -n 's/^Worktree ready at //p' "$log" | tail -1)
    [[ -n "$feature" && -n "$plan" && -n "$wpid" ]] || { skipped=$((skipped + 1)); continue; }

    # Already registered with a live builder: nothing to adopt.
    if registry_exists "$feature" && pid_alive "$(registry_get "$feature" .builder_pid)" "$(registry_get "$feature" .builder_started)"; then
      echo "skip $feature: already registered (builder $(registry_get "$feature" .builder_pid) alive)"
      continue
    fi

    # The logged watcher must still be this feature's watcher.
    if ! ps -o command= -p "$wpid" 2>/dev/null | grep -q "watcher.sh --loop .* ${feature}\$"; then
      skipped=$((skipped + 1)); continue
    fi
    local bpid
    bpid=$(ps -o ppid= -p "$wpid" 2>/dev/null | tr -d ' ')
    if [[ -z "$bpid" || "$bpid" == "1" ]] || ! kill -0 "$bpid" 2>/dev/null; then
      echo "skip $feature: watcher $wpid has no live launching builder"
      skipped=$((skipped + 1)); continue
    fi

    local build_repo="$repo" wt=false
    [[ -n "$worktree_path" ]] && { build_repo="$worktree_path"; wt=true; }
    registry_register "$feature" "$build_repo" "$repo" "$plan" "$branch" "$bpid" "$wpid" "$log" "$wt"
    local started epoch
    started=$(pid_started "$bpid")
    epoch=$(_lstart_epoch "$started")
    registry_update "$feature" '.launched_epoch = ($e|tonumber) | .state_since = ($e|tonumber)
      | .launched_at = ($e|tonumber|todate) | .last_action = $a | .adopted = true' \
      --arg e "${epoch:-$(date +%s)}" --arg a "adopted from $(basename "$log")"
    echo "adopted $feature: builder $bpid (started $started), watcher $wpid, repo $build_repo, log $log"
    adopted=$((adopted + 1))
  done
  echo "adopt: $adopted adopted, $skipped logs skipped"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  adopt_all
fi

#!/usr/bin/env bash
# Build registry: one JSON file per walkaway build at $WALKAWAY_HOME/registry/<feature>.json.
#
# PIDs are recorded from the launch itself (builder = the walkaway process that execs the builder,
# watcher = the PID watcher_start spawned), never by matching process names. builder_started holds
# the process start time so a recycled PID is never mistaken for the builder.
#
# Source this file; all functions are prefixed registry_.

WALKAWAY_HOME="${WALKAWAY_HOME:-$HOME/.walkaway-cli}"

registry_dir() { echo "${WALKAWAY_HOME}/registry"; }
registry_file() { echo "$(registry_dir)/$1.json"; }
queue_dir() { echo "${WALKAWAY_HOME}/queue"; }

# Queue key for a repo: basename of the main repo root (worktrees share their source repo's queue).
registry_repo_key() { basename "$1"; }

# Per-repo launch lock: one process at a time reads/rewrites <repo>'s queue, checks for an active build and launches.
# mkdir lock at $WALKAWAY_HOME/state/queue-<key>.lock holding the owner's pid. Waits up to WALKAWAY_QUEUE_LOCK_WAIT
# seconds (120); a lock whose pid is dead (or that never got a pid within 10 s) is stale and is taken over.
# Callers run in a subshell and release with `trap 'queue_unlock <key>' EXIT` so every exit path unlocks.
_queue_lock_dir() { echo "${WALKAWAY_HOME}/state/queue-$1.lock"; }
queue_lock() {
  local lock pid waited=0 me="${BASHPID:-$$}"
  lock=$(_queue_lock_dir "$1"); mkdir -p "${WALKAWAY_HOME}/state"
  while ! mkdir "$lock" 2>/dev/null; do
    pid=$(cat "$lock/pid" 2>/dev/null || true)
    if { [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; } ||
       { [[ -z "$pid" ]] && (( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || date +%s) > 10 )); }; then
      # Stale: move it aside atomically (only one waiter wins the rename), then retry mkdir.
      mv "$lock" "${lock}.stale.${me}" 2>/dev/null && rm -rf "${lock}.stale.${me}"
      continue
    fi
    (( waited >= ${WALKAWAY_QUEUE_LOCK_WAIT:-120} )) && return 1
    sleep 1; waited=$((waited + 1))
  done
  echo "$me" > "$lock/pid"
}
# Releases the lock only if this process holds it.
queue_unlock() {
  local lock
  lock=$(_queue_lock_dir "$1")
  [[ "$(cat "$lock/pid" 2>/dev/null)" == "${BASHPID:-$$}" ]] && rm -rf "$lock"
  return 0
}

# Start time of a PID as printed by ps (empty if the PID is gone).
pid_started() {
  [[ -n "${1:-}" && "$1" != "null" ]] || return 0
  ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# True if PID is alive AND (when an expected start time is given) is the same process.
pid_alive() {
  local pid="${1:-}" expected="${2:-}"
  [[ -n "$pid" && "$pid" != "null" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ -z "$expected" || "$expected" == "null" ]] && return 0
  [[ "$(pid_started "$pid")" == "$expected" ]]
}

registry_exists() { [[ -f "$(registry_file "$1")" ]]; }

# registry_get <feature> <jq-path>   e.g. registry_get foo .builder_pid
registry_get() {
  local f
  f=$(registry_file "$1")
  [[ -f "$f" ]] || return 1
  jq -r "$2 // empty" "$f"
}

# registry_update <feature> <jq-filter> [jq args...]  - atomic rewrite (tmp + mv).
registry_update() {
  local feature="$1" filter="$2"
  shift 2
  local f tmp
  f=$(registry_file "$feature")
  [[ -f "$f" ]] || { echo "registry: no entry for $feature" >&2; return 1; }
  tmp="${f}.tmp.$$"
  jq "$@" "$filter" "$f" > "$tmp" && mv "$tmp" "$f"
}

# registry_register <feature> <repo> <repo_root> <plan> <branch> <builder_pid> <watcher_pid> [launch_log] [worktree]
# Creates the entry or refreshes it on relaunch. Counters (resume_count, gate_rejections, approvals)
# survive relaunches so the supervisor's caps hold across them. report_baseline is cleared on every launch;
# an auto-resume sets it back to the pre-resume baseline (a resume never invalidates a committed report).
registry_register() {
  local feature="$1" repo="$2" repo_root="$3" plan="$4" branch="$5" builder_pid="$6" watcher_pid="$7"
  local launch_log="${8:-}" worktree="${9:-false}"
  local dir f now_iso now_epoch started queue_next=""
  dir=$(registry_dir)
  mkdir -p "$dir"
  f=$(registry_file "$feature")
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  now_epoch=$(date +%s)
  started=$(pid_started "$builder_pid")

  local qfile
  qfile="$(queue_dir)/$(registry_repo_key "$repo_root").txt"
  if [[ -f "$qfile" ]]; then
    queue_next=$(grep -v '^[[:space:]]*\(#\|$\)' "$qfile" | head -1 || true)
  fi

  local base='{}'
  [[ -f "$f" ]] && base=$(cat "$f")
  local tmp="${f}.tmp.$$"
  jq -n --argjson base "$base" \
    --arg feature "$feature" --arg repo "$repo" --arg repo_root "$repo_root" --arg plan "$plan" \
    --arg branch "$branch" --arg builder_pid "$builder_pid" --arg builder_started "$started" \
    --arg watcher_pid "$watcher_pid" --arg launched_at "$now_iso" --argjson launched_epoch "$now_epoch" \
    --arg launch_log "$launch_log" --arg queue_next "$queue_next" --argjson worktree "$worktree" '
    def num($s): if $s == "" then null else ($s | tonumber) end;
    $base + {
      feature: $feature, repo: $repo, repo_root: $repo_root, plan: $plan, branch: $branch,
      builder_pid: num($builder_pid), builder_started: $builder_started,
      watcher_pid: num($watcher_pid), launched_at: $launched_at, launched_epoch: $launched_epoch,
      launch_log: $launch_log, worktree: $worktree,
      resume_count: ($base.resume_count // 0), gate_rejections: ($base.gate_rejections // 0),
      approvals: ($base.approvals // 0), launch_count: (($base.launch_count // 0) + 1),
      queue_next: (if $queue_next == "" then null else $queue_next end),
      state: "LAUNCHED", state_since: $launched_epoch,
      last_action: (if ($base.launch_count // 0) == 0 then "launched" else "relaunched" end),
      operator_pid: null, report_baseline: null
    }' > "$tmp" && mv "$tmp" "$f"
}

# Lists registered features, one per line.
registry_list() {
  local dir
  dir=$(registry_dir)
  [[ -d "$dir" ]] || return 0
  local f
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    basename "$f" .json
  done
}

_fmt_age() {
  local s="$1"
  if (( s < 3600 )); then echo "$((s / 60))m"
  elif (( s < 86400 )); then echo "$((s / 3600))h$(( (s % 3600) / 60 ))m"
  else echo "$((s / 86400))d$(( (s % 86400) / 3600 ))h"
  fi
}

# One table from the registry: feature, repo, state, age, last action.
registry_status() {
  local now features
  now=$(date +%s)
  features=$(registry_list)
  if [[ -z "$features" ]]; then
    echo "No builds registered in $(registry_dir)."
    return 0
  fi
  local tick_file="${WALKAWAY_HOME}/state/supervisor-last-tick"
  if [[ -f "$tick_file" ]]; then
    echo "supervisor last tick: $(date -r "$(cat "$tick_file")" '+%Y-%m-%d %H:%M:%S %Z')"
  else
    echo "supervisor last tick: never"
  fi
  {
    printf 'FEATURE\tREPO\tSTATE\tAGE\tIN-STATE\tLAST ACTION\n'
    local feature f
    while IFS= read -r feature; do
      f=$(registry_file "$feature")
      jq -r --argjson now "$now" '
        [.feature, (.repo_root // .repo | split("/") | last), (.state // "?"),
         ($now - (.launched_epoch // $now)), ($now - (.state_since // .launched_epoch // $now)),
         (.last_action // "-")] | @tsv' "$f" |
      while IFS=$'\t' read -r feat repo state age in_state action; do
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$feat" "$repo" "$state" "$(_fmt_age "$age")" "$(_fmt_age "$in_state")" "$action"
      done
    done <<< "$features"
  } | column -t -s $'\t'
}

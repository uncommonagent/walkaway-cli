#!/usr/bin/env bash
# Walkaway build supervisor. Run every 2 minutes by launchd (com.jimross.walkaway-supervisor).
#
#   supervisor.sh tick                 classify every registered build, notify transitions, dispatch actions
#   supervisor.sh classify <feature>   print "<STATE>\t<reason>" for one build (no side effects)
#   supervisor.sh adopt                backfill the registry from live walkaway launch logs (see adopt.sh)
#
# States: RUNNING, STALLED, STOPPED, DIED, DONE, MERGED, ESCALATED. Every state change sends exactly one
# ntfy line "<feature>: <STATE> - <action taken>". While $WALKAWAY_HOME/jobs.enabled exists, each tick also
# watches the scheduled jobs in jobs.yaml (lib/jobs.sh tick; job lines read "job <name>: <STATE> - ..."). Judgment calls (failure triage, merge gate) run as a
# detached operator job (operator.sh) so one slow gate never blocks the 2-minute tick for other builds.

set -uo pipefail

SUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/registry.sh
source "${SUP_DIR}/registry.sh"
# shellcheck source=lib/notify.sh
source "${SUP_DIR}/notify.sh"

WALKAWAY_STALL_SECS="${WALKAWAY_STALL_SECS:-2400}"          # 40 min without activity = STALLED
WALKAWAY_DIED_GRACE_SECS="${WALKAWAY_DIED_GRACE_SECS:-180}"  # PID gone but active < 3 min ago = still exiting, not DIED
WALKAWAY_GH_CMD="${WALKAWAY_GH_CMD:-gh}"
WALKAWAY_HEARTBEAT_HOURS="${WALKAWAY_HEARTBEAT_HOURS:-09 13 17}"
WALKAWAY_CLAUDE_PROJECTS="${WALKAWAY_CLAUDE_PROJECTS:-$HOME/.claude/projects}"
SUP_STATE_DIR="${WALKAWAY_HOME}/state"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ── signals ──────────────────────────────────────────────────────────────────

_mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }

# Newest mtime of files matching a glob (0 if none).
_newest() {
  local newest=0 f m
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    m=$(_mtime "$f")
    (( m > newest )) && newest=$m
  done
  echo "$newest"
}

# Last activity epoch: newest file under handoff/, branch HEAD commit time, and the newest Claude Code
# transcript for the build's working dir (a working builder appends to it continuously).
supervisor_activity() {
  local repo="$1" branch="$2"
  local a=0 m
  if [[ -d "$repo/handoff" ]]; then
    m=$(find "$repo/handoff" -type f -not -name '.*' -print0 2>/dev/null | xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1)
    [[ -n "$m" ]] && (( m > a )) && a=$m
  fi
  m=$(git -C "$repo" log -1 --format=%ct "$branch" 2>/dev/null || true)
  [[ -n "$m" ]] && (( m > a )) && a=$m
  local slug
  slug=$(echo "$repo" | sed 's#[/.]#-#g')
  if [[ -d "$WALKAWAY_CLAUDE_PROJECTS/$slug" ]]; then
    m=$(_newest "$WALKAWAY_CLAUDE_PROJECTS/$slug"/*.jsonl)
    (( m > a )) && a=$m
  fi
  echo "$a"
}

# PR JSON for the branch ({} when there is none or gh fails).
supervisor_pr_json() {
  local repo="$1" branch="$2" out
  out=$(cd "$repo" 2>/dev/null && "$WALKAWAY_GH_CMD" pr view "$branch" --json number,state,url,headRefOid,mergeStateStatus,statusCheckRollup 2>/dev/null) || out=""
  [[ -n "$out" ]] && echo "$out" || echo '{}'
}

# green | pending | failed  from a PR JSON's statusCheckRollup (no checks configured = green).
supervisor_checks() {
  jq -r '
    [.statusCheckRollup[]? |
      if .__typename == "StatusContext" or (.state? != null and .conclusion? == null and .status? == null) then
        (if .state == "SUCCESS" then "ok" elif (.state == "PENDING" or .state == "EXPECTED") then "pending" else "failed" end)
      else
        (if (.status // "COMPLETED") != "COMPLETED" then "pending"
         elif ((.conclusion // "") | IN("SUCCESS","NEUTRAL","SKIPPED")) then "ok"
         else "failed" end)
      end] as $s
    | if ($s | index("failed")) then "failed" elif ($s | index("pending")) then "pending" else "green" end' <<< "$1"
}

# Newest failure report of THIS feature -> "<mtime>\t<path>" (nothing if none). Only the documented names
# match: failure-report-<feature>.md and failure-report-<feature>-{phase,codex,context}*.md, so a build
# named demo never consumes failure-report-demo-next-phase-3.md. Shared by classify and operator triage.
supervisor_failure_report() {
  local repo="$1" feature="$2" f m best="" bm=0
  for f in "$repo/handoff/failure-report-$feature.md" \
           "$repo/handoff/failure-report-$feature"-{phase,codex,context}*.md; do
    [[ -f "$f" ]] || continue
    m=$(_mtime "$f")
    if (( m > bm )); then bm=$m; best=$f; fi
  done
  [[ -n "$best" ]] && printf '%s\t%s\n' "$bm" "$best"
  return 0
}

# Commit epoch of the build report at the branch head: the newest commit on <branch> that touched
# handoff/build-report-<feature>.md, provided the file exists in the branch tip (0 otherwise). An uncommitted
# report never counts: a builder that dies before committing it is resumed to finish the commit.
supervisor_report_commit() {
  local repo="$1" branch="$2" feature="$3" path c
  path="handoff/build-report-$feature.md"
  git -C "$repo" cat-file -e "$branch:$path" 2>/dev/null || { echo 0; return 0; }
  c=$(git -C "$repo" log -1 --format=%ct "$branch" -- "$path" 2>/dev/null)
  echo "${c:-0}"
}

# True when the plan says the build opens no PR yet (then a committed build report alone is DONE).
supervisor_plan_no_pr() {
  [[ -f "$1" ]] && grep -qiE 'no PR yet|do not open a PR|PR: none' "$1"
}

# ── classification ───────────────────────────────────────────────────────────

# supervisor_classify <feature>  ->  "<STATE>\t<reason>"
supervisor_classify() {
  local feature="$1" f
  f=$(registry_file "$feature")
  [[ -f "$f" ]] || { printf 'UNKNOWN\tnot registered\n'; return 1; }

  local repo branch launched state pid started
  repo=$(jq -r '.repo' "$f"); branch=$(jq -r '.branch' "$f")
  launched=$(jq -r '.launched_epoch // 0' "$f"); state=$(jq -r '.state // ""' "$f")
  pid=$(jq -r '.builder_pid // empty' "$f"); started=$(jq -r '.builder_started // empty' "$f")

  if [[ "$state" == "MERGED" ]]; then printf 'MERGED\tterminal\n'; return 0; fi

  local pr pr_state pr_num checks
  pr=$(supervisor_pr_json "$repo" "$branch")
  pr_state=$(jq -r '.state // ""' <<< "$pr"); pr_num=$(jq -r '.number // ""' <<< "$pr")
  if [[ "$pr_state" == "MERGED" ]]; then printf 'MERGED\tPR #%s merged\n' "$pr_num"; return 0; fi
  if [[ "$state" == "ESCALATED" ]]; then printf 'ESCALATED\twaiting for Jim\n'; return 0; fi

  local fail fail_m=0
  fail=$(supervisor_failure_report "$repo" "$feature")
  [[ -n "$fail" ]] && fail_m=${fail%%$'\t'*}
  if (( fail_m > launched )); then printf 'STOPPED\t%s\n' "$(basename "${fail#*$'\t'}")"; return 0; fi

  # DONE first (11/13 bf-deals-ingest-fix: a builder that committed its report and exited read as DIED because
  # CI was still pending, then every resume moved launched_epoch past the report). A build report committed at
  # the branch head since the report baseline is DONE whether or not the builder is still alive. The baseline
  # is the last launch that was NOT an auto-resume (.report_baseline), so a resume never invalidates a report.
  local report_c baseline plan
  baseline=$(jq -r '.report_baseline // .launched_epoch // 0' "$f"); plan=$(jq -r '.plan // ""' "$f")
  report_c=$(supervisor_report_commit "$repo" "$branch" "$feature")
  if (( report_c > 0 && report_c >= baseline )); then
    if [[ "$pr_state" == "OPEN" ]]; then
      checks=$(supervisor_checks "$pr")
      case "$checks" in
        green)  printf 'DONE\tPR #%s checks green\n' "$pr_num"; return 0 ;;
        failed) printf 'STOPPED\tci-failed on PR #%s after build report\n' "$pr_num"; return 0 ;;
        *)      printf 'DONE\tPR #%s checks pending\n' "$pr_num"; return 0 ;;
      esac
    fi
    if supervisor_plan_no_pr "$plan"; then printf 'DONE\tno PR (plan says no PR yet)\n'; return 0; fi
    if ! pid_alive "$pid" "$started"; then printf 'STOPPED\tbuild report at branch head but no open PR\n'; return 0; fi
  fi

  local act now idle
  act=$(supervisor_activity "$repo" "$branch"); now=$(date +%s)
  (( act < launched )) && act=$launched
  idle=$(( now - act ))
  if ! pid_alive "$pid" "$started"; then
    # DIED needs all three: PID gone, no build report at the branch head (above), and quiet past the grace.
    if (( idle < WALKAWAY_DIED_GRACE_SECS )); then
      printf 'RUNNING\tbuilder pid %s exited %ss after last activity (grace %ss)\n' "$pid" "$idle" "$WALKAWAY_DIED_GRACE_SECS"; return 0
    fi
    printf 'DIED\tbuilder pid %s gone (or recycled), no build report at branch head, quiet %sm\n' "$pid" "$(( idle / 60 ))"; return 0
  fi

  if (( idle >= WALKAWAY_STALL_SECS )); then printf 'STALLED\tno activity %sm\n' "$(( idle / 60 ))"; return 0; fi
  printf 'RUNNING\tbuilder pid %s, active %sm ago\n' "$pid" "$(( idle / 60 ))"
}

# ── transitions ──────────────────────────────────────────────────────────────

# supervisor_transition <feature> <state> <action> [priority]
# Records the state; sends exactly one ntfy when (and only when) the state changes.
supervisor_transition() {
  local feature="$1" new="$2" action="$3" priority="${4:-default}" old
  old=$(registry_get "$feature" .state)
  if [[ "$old" == "$new" ]]; then
    registry_update "$feature" '.last_action = $a' --arg a "$action"
    return 0
  fi
  registry_update "$feature" '.state = $s | .state_since = ($now|tonumber) | .last_action = $a' \
    --arg s "$new" --arg now "$(date +%s)" --arg a "$action"
  _log "$feature: $old -> $new - $action"
  notify_line "$feature: $new - $action" "$priority"
}

_operator_alive() {
  local opid
  opid=$(registry_get "$1" .operator_pid)
  [[ -n "$opid" ]] && kill -0 "$opid" 2>/dev/null
}

# Start a detached operator job (triage | gate) and record its PID.
_operator_spawn() {
  local feature="$1" mode="$2" log
  log="${WALKAWAY_HOME}/logs/operator-${feature}.log"
  mkdir -p "${WALKAWAY_HOME}/logs"
  nohup bash "${SUP_DIR}/operator.sh" "$mode" "$feature" >> "$log" 2>&1 < /dev/null &
  local opid=$!
  disown "$opid" 2>/dev/null || true
  registry_update "$feature" '.operator_pid = ($p|tonumber) | .operator_launch = .launch_count | .operator_mode = $m' \
    --arg p "$opid" --arg m "$mode"
  echo "$opid"
}

# DONE: the merge gate starts only on green checks (the gate itself re-verifies CI). Pending CI or a plan with
# no PR yet records DONE (one ntfy on entry) and waits; nothing resumes or relaunches a finished builder.
_handle_done() {
  local feature="$1" reason="$2"
  if [[ "$reason" == *"checks green"* ]]; then
    supervisor_transition "$feature" DONE "$reason; merge gate started"
    _operator_spawn "$feature" gate > /dev/null
  elif [[ "$reason" == *"checks pending"* ]]; then
    supervisor_transition "$feature" DONE "$reason; merge gate waits for green CI"
  else
    supervisor_transition "$feature" DONE "$reason; nothing to merge"
  fi
}

# Act on one build. Synchronous for DIED/STALLED/MERGED (fast, deterministic); detached operator for
# STOPPED (triage) and DONE (merge gate).
supervisor_handle() {
  local feature="$1" cls new reason old
  old=$(registry_get "$feature" .state)
  [[ "$old" == "MERGED" ]] && return 0

  if _operator_alive "$feature"; then
    registry_update "$feature" '.last_action = $a' --arg a "operator $(registry_get "$feature" .operator_mode) running"
    return 0
  fi

  cls=$(supervisor_classify "$feature") || return 0
  new=${cls%%$'\t'*}; reason=${cls#*$'\t'}

  # An operator job already ran for this launch and left the build unresolved: never loop, escalate.
  if [[ "$new" == "$old" && ( "$new" == "STOPPED" || "$new" == "DONE" ) ]] && \
     [[ "$(registry_get "$feature" .operator_launch)" == "$(registry_get "$feature" .launch_count)" ]]; then
    bash "${SUP_DIR}/operator.sh" escalate "$feature" "Operator exited without a decision on $new ($reason). How should this build proceed?"
    return 0
  fi

  # DONE is acted on per tick: the gate starts once the checks turn green, even if DONE was already recorded.
  [[ "$new" == "DONE" ]] && { _handle_done "$feature" "$reason"; return 0; }
  [[ "$new" == "$old" ]] && { registry_update "$feature" '.last_action = $a' --arg a "$reason"; return 0; }

  case "$new" in
    RUNNING)
      # First RUNNING after an operator relaunch carries the operator's action (approved fix / rejection / resume).
      local la
      la=$(registry_get "$feature" .last_action)
      [[ "$old" == "LAUNCHED" && "$la" == *"relaunched (builder pid"* ]] && reason="$la; $reason"
      supervisor_transition "$feature" RUNNING "$reason"
      ;;
    ESCALATED) supervisor_transition "$feature" ESCALATED "$reason" high ;;
    DIED|STALLED)
      supervisor_transition "$feature" "$new" "$reason; auto-resume starting"
      bash "${SUP_DIR}/operator.sh" resume "$feature" "$new: $reason"
      ;;
    STOPPED)
      supervisor_transition "$feature" STOPPED "$reason; operator triage started"
      _operator_spawn "$feature" triage > /dev/null
      ;;
    DONE) _handle_done "$feature" "$reason" ;;
    MERGED)
      bash "${SUP_DIR}/operator.sh" post-merge "$feature" "$reason"
      ;;
  esac
}

# ── heartbeat ────────────────────────────────────────────────────────────────

supervisor_heartbeat() {
  local hour slot last_file last
  hour=$(TZ=America/New_York date +%H)
  [[ " $WALKAWAY_HEARTBEAT_HOURS " == *" $hour "* ]] || return 0
  slot=$(TZ=America/New_York date +%Y-%m-%d-%H)
  last_file="${SUP_STATE_DIR}/heartbeat-last"
  last=$(cat "$last_file" 2>/dev/null || true)
  [[ "$slot" == "$last" ]] && return 0
  echo "$slot" > "$last_file"

  local lines="" feature st act any=0 jl
  while IFS= read -r feature; do
    [[ -n "$feature" ]] || continue
    st=$(registry_get "$feature" .state); act=$(registry_get "$feature" .last_action)
    case "$st" in MERGED) continue ;; RUNNING|ESCALATED) any=1 ;; esac
    lines+="$feature: $st - $act"$'\n'
  done < <(registry_list)
  # Scheduled jobs: any non-OK job (window opened) is listed and alone justifies the heartbeat.
  if [[ -f "${WALKAWAY_HOME}/jobs.enabled" ]]; then
    jl=$(bash "${SUP_DIR}/jobs.sh" heartbeat 2>/dev/null)
    [[ -n "$jl" ]] && { lines+="$jl"$'\n'; any=1; }
  fi
  (( any )) || return 0
  notify_line "${lines%$'\n'}"
}

# ── tick ─────────────────────────────────────────────────────────────────────

_lock_acquire() {
  local lock="${SUP_STATE_DIR}/supervisor.lock"
  mkdir -p "$SUP_STATE_DIR"
  if mkdir "$lock" 2>/dev/null; then
    echo $$ > "$lock/pid"; return 0
  fi
  local holder
  holder=$(cat "$lock/pid" 2>/dev/null || true)
  if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
    return 1
  fi
  # Stale lock from a dead tick: take it over.
  echo $$ > "$lock/pid"; return 0
}

_lock_release() { rm -rf "${SUP_STATE_DIR}/supervisor.lock"; }

supervisor_tick() {
  if ! _lock_acquire; then _log "another tick holds the lock; exiting"; return 0; fi
  trap _lock_release EXIT
  local feature
  while IFS= read -r feature; do
    [[ -n "$feature" ]] || continue
    supervisor_handle "$feature" || _log "$feature: handler error"
  done < <(registry_list)
  # Scheduled-job watching (jobs.yaml) runs while $WALKAWAY_HOME/jobs.enabled exists.
  if [[ -f "${WALKAWAY_HOME}/jobs.enabled" ]]; then
    bash "${SUP_DIR}/jobs.sh" tick || _log "jobs tick error"
  fi
  supervisor_heartbeat
  date +%s > "${SUP_STATE_DIR}/supervisor-last-tick"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    tick)     supervisor_tick ;;
    classify) supervisor_classify "${2:?feature}" ;;
    adopt)    bash "${SUP_DIR}/adopt.sh" ;;
    *) echo "Usage: supervisor.sh tick | classify <feature> | adopt" >&2; exit 1 ;;
  esac
fi

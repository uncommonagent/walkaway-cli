#!/usr/bin/env bash
# AC2 live drill. A second launchd agent (com.jimross.walkaway-supervisor-drill, every 120s) supervises a
# scratch world under tests/drill/work/: real walkaway launches, real stub-builder processes, real
# `claude -p` operator decisions, real ntfy pushes to a drill topic (captured via the ntfy JSON poll API).
# gh is gh-sim (scratch repos have a local bare origin, no GitHub remote).
#
# Scenarios (one scratch repo each; e and e2 share a repo + queue):
#   a  kill the builder mid-phase       -> DIED ntfy + auto-resume within 4 min
#   b  scoped failure report            -> operator approves + relaunch
#   c  failure report needing PROTECTED -> ESCALATED ntfy with one question, no relaunch
#   d  complete with bad evidence       -> merge-gate rejection directive + relaunch
#   e  complete with good evidence      -> merged + queued plan e2 launched
#
# Evidence is archived to handoff/drill-evidence-build-supervisor/.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=tests/drill/scratch.sh
source "$HERE/scratch.sh"

WORK="$HERE/work"
EVID="$ROOT/handoff/drill-evidence-build-supervisor"
LABEL="com.jimross.walkaway-supervisor-drill"
TOPIC="${DRILL_TOPIC:-jim-walkaway-drill-$(openssl rand -hex 4)}"
T0=$(date +%s)

if [[ "${1:-}" == "--clean" ]]; then
  WALKAWAY_SUPERVISOR_LABEL="$LABEL" WALKAWAY_HOME="$WORK/home" bash "$ROOT/install-supervisor.sh" --uninstall
  for f in "$WORK"/home/registry/*.json; do
    [[ -f "$f" ]] || continue
    for p in $(jq -r '.builder_pid, .watcher_pid, .operator_pid | select(. != null)' "$f"); do
      pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null
    done
  done
  rm -rf "$WORK"
  echo "drill torn down"
  exit 0
fi
if [[ -d "$WORK" ]]; then echo "tests/drill/work exists - run with --clean first" >&2; exit 1; fi
mkdir -p "$WORK"/{home/queue,home/logs,logs,gh,repos} "$EVID"

export WALKAWAY_HOME="$WORK/home" GH_SIM_DIR="$WORK/gh" WALKAWAY_LAUNCH_LOG_DIR="$WORK/logs"
export WALKAWAY_BUILDER_CMD="$HERE/stub-builder.sh" WALKAWAY_GH_CMD="$HERE/gh-sim.sh"
export NTFY_TOPIC="$TOPIC" WALKAWAY_CLAUDE_PROJECTS="$WORK/no-transcripts" WALKAWAY_MERGE_CHECK_WAIT=60

say() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$EVID/timeline.md"; }
reg() { jq -r "$2 // empty" "$WALKAWAY_HOME/registry/$1.json" 2>/dev/null; }
wait_for() { # timeout-secs description command...
  local limit="$1" what="$2" start
  shift 2
  start=$(date +%s)
  while ! "$@"; do
    (( $(date +%s) - start > limit )) && { say "TIMEOUT waiting for: $what"; return 1; }
    sleep 5
  done
  say "ok: $what (+$(( $(date +%s) - start ))s)"
}
launch() { # repo feature
  (cd "$1" || exit 1; nohup bash "$ROOT/walkaway.sh" "$1/handoff/build-plan-$2.md" > "$WORK/logs/walkaway-$2.log" 2>&1 < /dev/null &)
}

echo "# Drill timeline ($(date '+%Y-%m-%d %Z'))" > "$EVID/timeline.md"
say "topic: $TOPIC  work: $WORK"

# ── scratch world ────────────────────────────────────────────────────────────
RA=$(drill_make_repo "$WORK/repos" drill-ra drill-a);         drill_set_modes "$RA" drill-a work work
RB=$(drill_make_repo "$WORK/repos" drill-rb drill-b);         drill_set_modes "$RB" drill-b fail-scoped work
drill_failure "$RB" drill-b scoped
RC=$(drill_make_repo "$WORK/repos" drill-rc drill-c);         drill_set_modes "$RC" drill-c fail-protected
drill_failure "$RC" drill-c protected
RD=$(drill_make_repo "$WORK/repos" drill-rd drill-d);         drill_set_modes "$RD" drill-d complete-bad work
drill_evidence "$RD" bad
RE=$(drill_make_repo "$WORK/repos" drill-re drill-e drill-e2); drill_set_modes "$RE" drill-e complete-good
drill_set_modes "$RE" drill-e2 work
drill_evidence "$RE" good
echo "$RE/handoff/build-plan-drill-e2.md" > "$WALKAWAY_HOME/queue/drill-re.txt"

# ── drill supervisor agent (real launchd, 120s) ──────────────────────────────
x() { printf '    <key>%s</key><string>%s</string>\n' "$1" "$2"; }
WALKAWAY_EXTRA_ENV_XML="$(x NTFY_TOPIC "$TOPIC")
$(x GH_SIM_DIR "$GH_SIM_DIR")
$(x WALKAWAY_GH_CMD "$WALKAWAY_GH_CMD")
$(x WALKAWAY_BUILDER_CMD "$WALKAWAY_BUILDER_CMD")
$(x WALKAWAY_LAUNCH_LOG_DIR "$WALKAWAY_LAUNCH_LOG_DIR")
$(x WALKAWAY_CLAUDE_PROJECTS "$WALKAWAY_CLAUDE_PROJECTS")
$(x WALKAWAY_MERGE_CHECK_WAIT 60)
"
export WALKAWAY_EXTRA_ENV_XML WALKAWAY_SUPERVISOR_LABEL="$LABEL" WALKAWAY_LAUNCH_LOG_GLOB="$WORK/logs/none-*.log"
bash "$ROOT/install-supervisor.sh" 2>&1 | tee -a "$EVID/timeline.md"

# ── launch all five ──────────────────────────────────────────────────────────
for pair in "$RA drill-a" "$RB drill-b" "$RC drill-c" "$RD drill-d" "$RE drill-e"; do
  # shellcheck disable=SC2086
  launch $pair
done
wait_for 60 "5 builds registered" bash -c "ls '$WALKAWAY_HOME'/registry/*.json 2>/dev/null | wc -l | grep -q 5"

# (a) kill the builder mid-phase once the supervisor has seen it RUNNING
wait_for 300 "drill-a RUNNING" bash -c "[[ \$(jq -r .state '$WALKAWAY_HOME/registry/drill-a.json') == RUNNING ]]"
A_PID=$(reg drill-a .builder_pid)
KILL_AT=$(date +%s)
kill "$A_PID"
say "(a) killed drill-a builder pid $A_PID mid-phase at $(date -r "$KILL_AT" '+%H:%M:%S')"
wait_for 300 "drill-a relaunched" bash -c "[[ \$(jq -r .launch_count '$WALKAWAY_HOME/registry/drill-a.json') == 2 ]]"
A_RELAUNCH=$(reg drill-a .launched_epoch)
say "(a) auto-resume: new builder pid $(reg drill-a .builder_pid) launched $(( A_RELAUNCH - KILL_AT ))s after the kill (limit 240s)"

wait_for 900 "drill-b approved + relaunched" bash -c "[[ \$(jq -r .approvals '$WALKAWAY_HOME/registry/drill-b.json') == 1 && \$(jq -r .launch_count '$WALKAWAY_HOME/registry/drill-b.json') == 2 ]]"
wait_for 900 "drill-c ESCALATED" bash -c "[[ \$(jq -r .state '$WALKAWAY_HOME/registry/drill-c.json') == ESCALATED ]]"
wait_for 1500 "drill-d gate rejection relaunched" bash -c "[[ \$(jq -r .gate_rejections '$WALKAWAY_HOME/registry/drill-d.json') == 1 && \$(jq -r .launch_count '$WALKAWAY_HOME/registry/drill-d.json') == 2 ]]"
wait_for 1500 "drill-e MERGED" bash -c "[[ \$(jq -r .state '$WALKAWAY_HOME/registry/drill-e.json') == MERGED ]]"
wait_for 300 "drill-e2 launched from queue" test -f "$WALKAWAY_HOME/registry/drill-e2.json"
# Let one more tick record the relaunched builds as RUNNING.
wait_for 300 "relaunched builds RUNNING" bash -c "for f in drill-a drill-b drill-d drill-e2; do [[ \$(jq -r .state '$WALKAWAY_HOME/registry/'\$f.json) == RUNNING ]] || exit 1; done"

# ── capture + verify ntfy ────────────────────────────────────────────────────
sleep 5
curl -s "https://ntfy.sh/$TOPIC/json?poll=1&since=$T0" > "$EVID/ntfy-poll.json"
cp "$WALKAWAY_HOME/logs/ntfy.log" "$EVID/ntfy-local.log"
say "ntfy poll: $(wc -l < "$EVID/ntfy-poll.json" | tr -d ' ') messages on $TOPIC; local sends: $(wc -l < "$EVID/ntfy-local.log" | tr -d ' ')"
jq -r 'select(.event == "message") | [(.time | strftime("%H:%M:%S")), (.priority // 3 | tostring), .message] | @tsv' "$EVID/ntfy-poll.json" > "$EVID/ntfy-poll-messages.tsv"
# Exactly one ntfy per transition: the poll matches the local send log 1:1, and no feature repeats a state back-to-back.
poll_msgs=$(cut -f3- "$EVID/ntfy-poll-messages.tsv" | sort)
local_msgs=$(cut -f4- "$EVID/ntfy-local.log" | sort)
if [[ "$poll_msgs" == "$local_msgs" ]]; then say "ntfy poll == local send log (1:1)"; else say "MISMATCH between ntfy poll and local send log"; fi
dups=$(cut -f3- "$EVID/ntfy-poll-messages.tsv" | awk -F': ' '{split($2, s, " - "); k=$1; if (last[k] == s[1]) print "repeat: " $0; last[k] = s[1]}')
if [[ -z "$dups" ]]; then say "no repeated state per feature (one ntfy per transition)"; else say "REPEATS: $dups"; fi

# ── archive ──────────────────────────────────────────────────────────────────
mkdir -p "$EVID/registry" "$EVID/operator-logs" "$EVID/plans" "$EVID/launches"
cp "$WALKAWAY_HOME"/registry/*.json "$EVID/registry/"
cp "$WALKAWAY_HOME/logs/supervisor.log" "$EVID/supervisor.log"
cat "$WALKAWAY_HOME"/logs/operator-*.log > "$EVID/operator-jobs.log" 2>/dev/null
cp "$GH_SIM_DIR/calls.log" "$EVID/gh-sim-calls.log"
for r in "$RA" "$RB" "$RC" "$RD" "$RE"; do
  cp "$r"/handoff/operator-log-*.md "$EVID/operator-logs/" 2>/dev/null
  cp "$r"/handoff/build-plan-*.md "$EVID/plans/" 2>/dev/null
  cp "$r"/.drill/launches-* "$EVID/launches/" 2>/dev/null
done
git -C "$WORK/repos/drill-re-origin.git" log --format='%h %ad %s' --date=iso main > "$EVID/drill-re-origin-main.log"
WALKAWAY_HOME="$WALKAWAY_HOME" bash "$ROOT/walkaway.sh" status > "$EVID/walkaway-status.txt"
say "archived to $EVID"
say "done in $(( $(date +%s) - T0 ))s; run tests/drill/run-drill.sh --clean to tear down"

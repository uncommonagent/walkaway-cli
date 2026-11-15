#!/usr/bin/env bash
# AC3 live drill for data-series gap watching (supervisor-v3-data). Real supervisor ticks (lib/supervisor.sh tick with
# data watching on) in a scratch $WALKAWAY_HOME, time travel via WALKAWAY_DATA_NOW, REAL headless `claude -p`
# diagnosis, REAL ntfy pushes to a drill topic (captured via the ntfy JSON poll API). Delete-free: the series are
# scratch series whose row counts live in fixture files; the "pulls" are scratch scripts that write those fixtures.
# Nothing reads or writes a real table, and no real pull is triggered.
#
# The owner repo is a throwaway scratch repo (origin = a scratch bare repo) and a registered busy build holds its
# one-builder slot, so the fix plan is QUEUED and never launched.
#
#   series         gap                                re-pull path                       expected ntfy
#   drill-repull   2026-11-17 missing (age 1)         land.sh (an existing path, works)  OPEN, CLOSED
#   drill-nopath   2026-11-12 missing (age 6)         scripts/pull.sh (yesterday only)   OPEN, FIXING, CLOSED
#                                                     -> 2 failed tries -> claude -> fix plan (--from/--to hook)
#                                                     queued -> simulated merge -> hook re-pulls 11-12 -> CLOSED
#   drill-lost     2026-11-16 missing (age 2)         none; historical "no"              OPEN, ESCALATED
# Evidence: handoff/supervisor-v3-data-evidence/ac3-drill/.
#
#   tests/drill/run-data-drill.sh            run the drill
#   tests/drill/run-data-drill.sh --clean    remove the scratch world

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$HERE/work-data"
EVID="$ROOT/handoff/supervisor-v3-data-evidence/ac3-drill"
TOPIC="${DRILL_TOPIC:-jim-walkaway-data-drill-$(openssl rand -hex 4)}"

if [[ "${1:-}" == "--clean" ]]; then
  for f in "$WORK"/home/registry/*.json; do [[ -f "$f" ]] && kill "$(jq -r .builder_pid "$f")" 2>/dev/null; done
  rm -rf "$WORK"; echo "data drill torn down"; exit 0
fi

rm -rf "$WORK" "$EVID"
mkdir -p "$WORK/fx" "$WORK/logs" "$WORK/bin" "$EVID"
T0=$(date +%s)
TRANSCRIPT="$EVID/drill-transcript.txt"
say() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$TRANSCRIPT"; }
PASS=0
FAIL=0
check() { local label="$1"; shift; if "$@"; then say "PASS: $label"; PASS=$((PASS + 1)); else say "FAIL: $label"; FAIL=$((FAIL + 1)); fi; }

export WALKAWAY_HOME="$WORK/home" NTFY_TOPIC="$TOPIC" WALKAWAY_HEARTBEAT_HOURS=off WALKAWAY_DATA_FILE="$WORK/series.yaml"
export WALKAWAY_DATA_FIXTURES="$WORK/fx" WALKAWAY_GH_CMD="$HERE/gh-sim.sh" GH_SIM_DIR="$WORK/gh"
export WALKAWAY_CLAUDE_PROJECTS="$WORK/none" WALKAWAY_LAUNCH_LOG_DIR="$WORK/logs" WALKAWAY_STALL_SECS=86400
unset WALKAWAY_NTFY_DISABLED WALKAWAY_OPERATOR_CMD WALKAWAY_DATA_OPERATOR WALKAWAY_DATA_TRIGGER_CMD WALKAWAY_DATA_GUARD_FIXTURE
mkdir -p "$WALKAWAY_HOME"
touch "$WALKAWAY_HOME/supervisor.enabled" "$WALKAWAY_HOME/data.enabled"
say "data drill start: topic $TOPIC, home $WALKAWAY_HOME"

# ── fixture "store" + the scratch pull scripts ───────────────────────────────
# land.sh <series> <from> <to> <count>: write <count> rows for every day from..to (stands in for a working pull).
cat > "$WORK/bin/land.sh" <<'SH'
#!/usr/bin/env bash
python3 - "$WALKAWAY_DATA_FIXTURES/$1.json" "$2" "$3" "$4" <<'PY'
import json, sys, datetime, os
p, a, b, c = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
x = datetime.date.fromisoformat(a); e = datetime.date.fromisoformat(b)
while x <= e:
    d[x.isoformat()] = c; x += datetime.timedelta(days=1)
json.dump(d, open(p, "w"))
PY
SH
chmod +x "$WORK/bin/land.sh"
fill() { "$WORK/bin/land.sh" "$@"; }

# Scratch owner repo: a daily pull that can only fetch YESTERDAY (the drill's "no date-range path" cause).
REPO="$WORK/pull-drill"
git init -q --bare "$WORK/pull-drill-origin.git"
git init -q -b main "$REPO"
mkdir -p "$REPO/scripts" "$REPO/handoff"
cat > "$REPO/scripts/pull.sh" <<'SH'
#!/usr/bin/env bash
# Daily showings pull (drill throwaway). Scheduled 06:00 ET. Fetches YESTERDAY's rows from the source API and
# upserts them into daily_showings (drill: the store is $WALKAWAY_DATA_FIXTURES/drill-nopath.json).
# Usage: scripts/pull.sh            no arguments: the date is always yesterday (see fetch_day below)
set -euo pipefail

fetch_day() {   # $1 = YYYY-MM-DD; the source API accepts any past date (GET /showings?date=...)
  python3 - "$WALKAWAY_DATA_FIXTURES/drill-nopath.json" "$1" <<'PY'
import json, sys, os
p, d = sys.argv[1], sys.argv[2]
s = json.load(open(p)) if os.path.exists(p) else {}
s[d] = 12
json.dump(s, open(p, "w"))
PY
}

day=$(date -v-1d +%F)   # always yesterday: there is no way to ask for another date
fetch_day "$day"
echo "pulled $day"
SH
chmod +x "$REPO/scripts/pull.sh"
printf '# pull-drill (throwaway)\nscripts/pull.sh: the daily pull. Table daily_showings, one row-set per day (floor 10).\n' > "$REPO/README.md"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=drill -c user.email=drill@example.invalid commit -qm "daily pull"
git -C "$REPO" remote add origin "$WORK/pull-drill-origin.git"
git -C "$REPO" push -q -u origin main 2>/dev/null
git -C "$REPO" remote set-head origin main

sleep 3600 > /dev/null 2>&1 &
BUSY=$!
bash -c "source '$ROOT/lib/registry.sh'; registry_register drill-busy '$REPO' '$REPO' '$REPO/handoff/build-plan-drill-busy.md' main '$BUSY' '' '' false" > /dev/null
say "drill-busy registered in $REPO (pid $BUSY): holds the one-builder slot so the fix plan queues"

# ── series config (JSON is valid YAML) ───────────────────────────────────────
jq -n --arg repo "$REPO" --arg land "$WORK/bin/land.sh" '{
  defaults: {lookback_days: 14, lookback_weeks: 4, lookback_months: 2, max_tries_per_day: 2, verify_after_mins: 30},
  vars: {}, sources: {scratch: {env_file: "/dev/null", url_var: "X", key_var: "Y", app_url: "http://127.0.0.1:9", cron_secret_var: "Z"}},
  guards: {},
  series: [
    {name: "drill-repull", title: "Drill: a series whose existing re-pull works", watch: true, owner_repo: $repo, source: "scratch",
     table: "t_repull", key: {column: "d", type: "date"}, filters: "", cadence: "daily", lag_days: 1, ready_by: "12:00",
     floor: 10, floor_basis: "drill", historical: "yes",
     repull: [{method: "command", ages: [1, 2, 3], verify_after_mins: 30, command: ($land + " drill-repull {from} {to} 12")}]},
    {name: "drill-nopath", title: "Drill: daily showings pull (scripts/pull.sh fetches yesterday only)", watch: true, owner_repo: $repo, source: "scratch",
     table: "daily_showings", key: {column: "obs_date", type: "date"}, filters: "", cadence: "daily", lag_days: 1, ready_by: "12:00",
     floor: 10, floor_basis: "drill", historical: "yes",
     repull: [{method: "command", ages: [1, 2, 3, 4, 5, 6, 7, 8], verify_after_mins: 30, command: ("bash " + $repo + "/scripts/pull.sh"), note: "re-runs the scheduled pull: it fetches yesterday only"},
              {method: "command", requires_fix: true, ages: "all", verify_after_mins: 30, command: ("bash " + $repo + "/scripts/pull.sh --from {from} --to {to}")}],
     fix_hook: "scripts/pull.sh --from YYYY-MM-DD --to YYYY-MM-DD pulls exactly that inclusive date range through fetch_day (the existing fetch/upsert path); no arguments keeps today'"'"'s behaviour (yesterday)"},
    {name: "drill-lost", title: "Drill: an as-of snapshot (cannot re-pull a past day)", watch: true, owner_repo: $repo, source: "scratch",
     table: "t_snapshot", key: {column: "d", type: "date"}, filters: "", cadence: "daily", lag_days: 0, ready_by: "13:00",
     floor: 4, floor_basis: "drill", historical: "no",
     repull: [{method: "command", ages: [0], verify_after_mins: 30, command: ($land + " drill-lost {from} {to} 4")}]}
  ]}' > "$WALKAWAY_DATA_FILE"

# Delete-free simulation: 14 days of rows, then holes. Nothing is deleted anywhere: the holes are fixture counts.
fill drill-repull 2026-11-01 2026-11-16 12
fill drill-nopath 2026-11-01 2026-11-17 12; fill drill-nopath 2026-11-12 2026-11-12 0
fill drill-lost 2026-11-01 2026-11-18 4; fill drill-lost 2026-11-16 2026-11-16 0

at() { TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "2026-11-18 $1" +%s; }
tick() { say "supervisor tick @ 2026-11-18 $1 ET (time travel)"; WALKAWAY_DATA_NOW=$(at "$1") bash "$ROOT/lib/supervisor.sh" tick >> "$WORK/supervisor.log" 2>&1; }
dst() { jq -r --arg p "$2" ".gaps[\$p].$3 // empty" "$WALKAWAY_HOME/data/state/$1.json" 2>/dev/null; }
sget() { jq -r ".$2 // empty" "$WALKAWAY_HOME/data/state/$1.json" 2>/dev/null; }
wait_operator() { # series: wait (<= 30 min) for the data operator to finish
  local i p
  for i in $(seq 1 360); do
    p=$(sget "$1" operator_pid)
    { [[ -z "$p" ]] || ! kill -0 "$p" 2>/dev/null; } && { say "$1 operator done after $((i * 5))s"; return 0; }
    sleep 5
  done
  say "$1 operator still running after 30 min"
}

# ── 1: 12:30 gaps open; re-pulls fire ────────────────────────────────────────
tick 12:30
check "drill-repull 11-17 OPEN -> re-pull fired (REPULLING)" [ "$(dst drill-repull 2026-11-17 state)" == "REPULLING" ]
check "drill-nopath 11-12 OPEN -> scheduled pull re-run (REPULLING)" [ "$(dst drill-nopath 2026-11-12 state)" == "REPULLING" ]
wait_operator drill-lost
check "drill-lost 11-16: source cannot re-pull -> ESCALATED (lost)" bash -c "[[ '$(dst drill-lost 2026-11-16 state)' == ESCALATED && '$(dst drill-lost 2026-11-16 lost)' == true ]]"

# ── 2: 12:32 the working re-pull landed rows -> CLOSED ───────────────────────
tick 12:32
check "drill-repull CLOSED rows 0 -> 12" bash -c "[[ '$(dst drill-repull 2026-11-17 state)' == CLOSED && '$(dst drill-repull 2026-11-17 rows_after)' == 12 ]]"
check "drill-nopath still REPULLING inside its verify window" [ "$(dst drill-nopath 2026-11-12 state)" == "REPULLING" ]

# ── 3: the yesterday-only pull never lands 11-12: two failed tries -> data operator (real claude) ──
tick 13:01
check "drill-nopath verify failed -> try 2 fired" bash -c "[[ '$(dst drill-nopath 2026-11-12 failed_tries)' == 1 && '$(dst drill-nopath 2026-11-12 state)' == REPULLING ]]"
tick 13:32
wait_operator drill-nopath
INC="$WALKAWAY_HOME/data-fixes/drill-nopath-2026-11-18/handoff/job-incident-drill-nopath-2026-11-18.md"
PLAN=$(ls "$WALKAWAY_HOME"/data-fixes/drill-nopath-2026-11-18/handoff/build-plan-fix-data-drill-nopath-*.md 2>/dev/null | head -1)
say "drill-nopath decision: $(sed -n '/^## Decision/{n;p;}' "$INC" 2>/dev/null)"
check "incident written (gaps, cause, evidence, fresh counts)" bash -c "grep -q '2026-11-12: missing - rows 0 / floor 10' '$INC' && grep -q '^## Cause' '$INC' && grep -q '^## Evidence' '$INC' && grep -q 'Fresh read-only counts' '$INC'"
check "drill-nopath FIXING: template-v2 fix plan queued behind drill-busy" bash -c "[[ '$(dst drill-nopath 2026-11-12 state)' == FIXING && -n '$PLAN' ]] && grep -qxF '$PLAN' '$WALKAWAY_HOME/queue/pull-drill.txt'"
check "fix plan not launched (no registry entry)" bash -c "! ls '$WALKAWAY_HOME'/registry/fix-data-drill-nopath-*.json > /dev/null 2>&1"
check "plan: template-v2 sections, owner repo, hook contract verbatim" bash -c "for s in '## Feature name' '## Branch name' '## Repo' '## Goal' '## Evidence' '## Quality rules' '## Date-range re-pull hook' '## Source of truth' '## Acceptance criteria' '## Gate checklist' '## Escalate to Jim' '## Phases' '## Do NOT build' '## Stop rules'; do grep -q \"^\$s\" '$PLAN' || exit 1; done; grep -qF '$REPO' '$PLAN' && grep -qF 'scripts/pull.sh --from YYYY-MM-DD --to YYYY-MM-DD pulls exactly that inclusive date range' '$PLAN'"

# ── 4: the fix "merges": the hook exists; the supervisor re-pulls exactly 11-12 -> CLOSED ──
FIXF=$(basename "$PLAN" .md); FIXF=${FIXF#build-plan-}
cat > "$REPO/scripts/pull.sh" <<'SH'
#!/usr/bin/env bash
# Daily showings pull (drill throwaway) - after the simulated fix: --from/--to re-pulls a date range.
set -euo pipefail
fetch_day() {
  python3 - "$WALKAWAY_DATA_FIXTURES/drill-nopath.json" "$1" <<'PY'
import json, sys, os
p, d = sys.argv[1], sys.argv[2]
s = json.load(open(p)) if os.path.exists(p) else {}
s[d] = 12
json.dump(s, open(p, "w"))
PY
}
if [[ "${1:-}" == "--from" ]]; then
  d="$2"; while [[ ! "$d" > "$4" ]]; do fetch_day "$d"; echo "pulled $d"; d=$(date -j -v+1d -f %F "$d" +%F); done
else
  fetch_day "$(date -v-1d +%F)"
fi
SH
git -C "$REPO" -c user.name=drill -c user.email=drill@example.invalid commit -qam "simulated $FIXF: --from/--to hook"
bash -c "source '$ROOT/lib/registry.sh'; registry_register '$FIXF' '$REPO' '$REPO' '$PLAN' 'feature/$FIXF' '' '' '' false; registry_update '$FIXF' '.state = \"MERGED\" | .last_action = \"drill: simulated merge\"'" > /dev/null
say "simulated merge of $FIXF (registry MERGED; scratch repo now has the --from/--to hook)"
tick 14:00
check "post-merge: the hook fired once for exactly 2026-11-12..2026-11-12" bash -c "grep -q 'drill-nopath: command bash .*/scripts/pull.sh --from 2026-11-12 --to 2026-11-12' '$WALKAWAY_HOME/logs/data-repull.log' && [[ \$(grep -c 'pull.sh --from' '$WALKAWAY_HOME/logs/data-repull.log') -eq 1 ]]"
tick 14:02
tick 14:04
check "drill-nopath CLOSED rows 0 -> 12 via the fix hook" bash -c "[[ '$(dst drill-nopath 2026-11-12 state)' == CLOSED && '$(dst drill-nopath 2026-11-12 rows_after)' == 12 ]] && [[ '$(dst drill-nopath 2026-11-12 closed_via)' == 'command (fix hook): '* ]]"

# ── capture + verify ntfy ────────────────────────────────────────────────────
sleep 5
curl -s "https://ntfy.sh/$TOPIC/json?poll=1&since=$T0" > "$EVID/ntfy-poll.json"
cp "$WALKAWAY_HOME/logs/ntfy.log" "$EVID/ntfy-local.log"
jq -r 'select(.event == "message") | [(.time | strftime("%H:%M:%S")), (.priority // 3 | tostring), .message] | @tsv' "$EVID/ntfy-poll.json" > "$EVID/ntfy-poll-messages.tsv"
say "ntfy poll: $(wc -l < "$EVID/ntfy-poll-messages.tsv" | tr -d ' ') messages on $TOPIC; local sends: $(wc -l < "$EVID/ntfy-local.log" | tr -d ' ')"
check "ntfy poll == local send log (1:1)" bash -c "[[ \"\$(cut -f3- '$EVID/ntfy-poll-messages.tsv' | sort)\" == \"\$(cut -f4- '$EVID/ntfy-local.log' | sort)\" ]]"
seq_of() { cut -f3 "$EVID/ntfy-poll-messages.tsv" | grep "^data $1: " | sed -E 's/^data [a-z-]+: ([A-Z]+) - .*/\1/' | tr '\n' ' '; }
say "polled transitions: drill-repull [$(seq_of drill-repull)] drill-nopath [$(seq_of drill-nopath)] drill-lost [$(seq_of drill-lost)]"
check "drill-repull: OPEN, CLOSED - one ntfy each" [ "$(seq_of drill-repull)" == "OPEN CLOSED " ]
check "drill-nopath: OPEN, FIXING, CLOSED - one ntfy each" [ "$(seq_of drill-nopath)" == "OPEN FIXING CLOSED " ]
check "drill-lost: OPEN, ESCALATED - one ntfy each" [ "$(seq_of drill-lost)" == "OPEN ESCALATED " ]
check "ESCALATED is priority high (ntfy 4) on the wire" bash -c "awk -F'\t' '\$3 ~ /^data drill-lost: ESCALATED/ {print \$2}' '$EVID/ntfy-poll-messages.tsv' | grep -qx 4"
check "REPULLING never pinged" bash -c "! grep -q 'REPULLING' '$EVID/ntfy-poll-messages.tsv'"

# ── archive ──────────────────────────────────────────────────────────────────
cp "$INC" "$EVID/" 2>/dev/null
[[ -n "$PLAN" ]] && cp "$PLAN" "$EVID/"
cp "$WALKAWAY_HOME"/data-fixes/drill-lost-2026-11-18/handoff/job-incident-*.md "$EVID/" 2>/dev/null
cp "$WALKAWAY_HOME"/data-fixes/drill-nopath-2026-11-18/handoff/evidence-*.json "$EVID/" 2>/dev/null
mkdir -p "$EVID/state"; cp "$WALKAWAY_HOME"/data/state/drill-*.json "$EVID/state/"
cp "$WALKAWAY_HOME"/queue/*.txt "$EVID/" 2>/dev/null
cp "$WALKAWAY_HOME/logs/data-repull.log" "$EVID/data-repull.log" 2>/dev/null
grep -h 'data:' "$WORK/supervisor.log" > "$EVID/supervisor-data-transitions.log" 2>/dev/null
cat "$WALKAWAY_HOME"/logs/data-operator-*.log > "$EVID/data-operator.log" 2>/dev/null
cp "$WALKAWAY_DATA_FILE" "$EVID/drill-series.json"
WALKAWAY_DATA_NOW=$(at 14:04) bash "$ROOT/walkaway.sh" status > "$EVID/walkaway-status-drill.txt" 2>&1
kill "$BUSY" 2>/dev/null

say "data drill done: $PASS passed, $FAIL failed (topic $TOPIC)"
[[ "$FAIL" -eq 0 ]]

#!/usr/bin/env bash
# Gap detection + gap state tests (lib/data.sh) on scratch series (tests/fixtures/data/series-test.yaml) and on the
# REAL data/series.yaml entries with fixture counts from real incidents. No network: counts come from
# WALKAWAY_DATA_FIXTURES, time is WALKAWAY_DATA_NOW, ntfy is disabled (lines are still logged).
# shellcheck disable=SC2034  # n1/n2 are read inside check's eval strings
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export WALKAWAY_NTFY_DISABLED=1 WALKAWAY_HEARTBEAT_HOURS=off
TEST_YAML="$ROOT/tests/fixtures/data/series-test.yaml"

fresh() { # fresh scratch home + fixture dir
  S=$(mktemp -d); mkdir -p "$S/fx"
  export WALKAWAY_HOME="$S" WALKAWAY_DATA_FIXTURES="$S/fx" WALKAWAY_DATA_FILE="$TEST_YAML" WALKAWAY_DATA_COUNT_LOG="$S/counts.log"
  export WALKAWAY_DATA_TRIGGER_CMD="$ROOT/tests/fixtures/data/trigger-stub.sh"
}
# opened <series> <period>: the gap was opened (data_evaluate may already have moved it on to REPULLING)
opened() { [[ "$(gst "$1" "$2" state)" == OPEN || "$(gst "$1" "$2" state)" == REPULLING ]]; }
at() { export WALKAWAY_DATA_NOW; WALKAWAY_DATA_NOW=$(TZ=America/New_York date -j -f '%Y-%m-%d %H:%M' "$1" +%s); }
# fill <series> <from> <to> <count>: set fixture counts for every day in [from, to]
fill() {
  python3 - "$S/fx/$1.json" "$2" "$3" "$4" <<'PY'
import json, sys, datetime, os
p, a, b, c = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
x = datetime.date.fromisoformat(a); e = datetime.date.fromisoformat(b)
while x <= e:
    d[x.isoformat()] = c; x += datetime.timedelta(days=1)
json.dump(d, open(p, "w"))
PY
}
setc() { python3 - "$S/fx/$1.json" "$2" "$3" <<'PY'
import json, sys, os
p = sys.argv[1]; d = json.load(open(p)) if os.path.exists(p) else {}
d[sys.argv[2]] = int(sys.argv[3]); json.dump(d, open(p, "w"))
PY
}
ev() { bash "$ROOT/lib/data.sh" evaluate "$1" > /dev/null 2>&1; }
gst() { jq -r --arg p "$2" ".gaps[\$p].$3 // empty" "$S/data/state/$1.json" 2>/dev/null; }
ntfy_n() { local n; n=$(grep -c "data $1: $2" "$S/logs/ntfy.log" 2>/dev/null); echo "${n:-0}"; }

echo "D1 missing days past ready_by -> OPEN, one grouped ntfy listing the dates"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; setc scratch-daily 2026-11-12 0; setc scratch-daily 2026-11-13 0; setc scratch-daily 2026-11-14 0
ev scratch-daily
check "11-12 OPEN missing" '[[ "$(gst scratch-daily 2026-11-12 state)" == OPEN && "$(gst scratch-daily 2026-11-12 status)" == missing ]]'
check "11-14 OPEN, rows_before 0" '[[ "$(gst scratch-daily 2026-11-14 state)" == OPEN && "$(gst scratch-daily 2026-11-14 rows_before)" == 0 ]]'
check "complete days are not gaps" '[[ -z "$(gst scratch-daily 2026-11-15 state)" ]]'
check "exactly one OPEN ntfy, consecutive dates as a range" '[[ "$(ntfy_n scratch-daily OPEN)" == 1 ]] && grep -q "OPEN - 2026-11-12..11-14 missing (0/10 rows)" "$S/logs/ntfy.log"'
ev scratch-daily
check "a second tick does not re-notify" '[[ "$(ntfy_n scratch-daily OPEN)" == 1 ]]'

echo "D2 short day (under the floor) -> OPEN short with rows"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; setc scratch-daily 2026-11-16 4
ev scratch-daily
check "11-16 opened short rows 4" 'opened scratch-daily 2026-11-16 && [[ "$(gst scratch-daily 2026-11-16 status)" == short && "$(gst scratch-daily 2026-11-16 rows_before)" == 4 ]]'
check "ntfy says short 4/10" 'grep -q "OPEN - 2026-11-16 short (4/10 rows)" "$S/logs/ntfy.log"'
setc scratch-daily 2026-11-16 10
ev scratch-daily
check "exactly at the floor = complete -> CLOSED" '[[ "$(gst scratch-daily 2026-11-16 state)" == CLOSED ]]'

echo "D3 lag-aware: the newest period is not judged before lag + ready_by"
fresh; at "2026-11-18 11:59"
fill scratch-daily 2026-11-01 2026-11-16 12      # 11-17 has no rows yet (lands 11-18 by 12:00)
ev scratch-daily
check "11-17 not a gap at 11:59 on 11-18" '[[ -z "$(gst scratch-daily 2026-11-17 state)" ]]'
check "today (lag 1) never judged" '[[ -z "$(gst scratch-daily 2026-11-18 state)" ]]'
at "2026-11-18 12:00"; ev scratch-daily
check "11-17 opened at its ready_by 12:00" 'opened scratch-daily 2026-11-17'

echo "D4 weekday cadence: weekend days without rows are not gaps"
fresh; at "2026-11-18 13:00"
fill scratch-weekday 2026-11-02 2026-11-17 3; setc scratch-weekday 2026-11-14 0; setc scratch-weekday 2026-11-15 0; setc scratch-weekday 2026-11-16 0
ev scratch-weekday
check "Sat 11-14 / Sun 11-15 not gaps" '[[ -z "$(gst scratch-weekday 2026-11-14 state)" && -z "$(gst scratch-weekday 2026-11-15 state)" ]]'
check "Mon 11-16 missing -> OPEN" '[[ "$(gst scratch-weekday 2026-11-16 state)" == OPEN ]]'
check "weekend periods never counted" '! grep -qE "scratch-weekday 2026-11-1[45]" "$S/counts.log"'

echo "D5 rows land -> CLOSED with rows before/after, one CLOSED ntfy"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; setc scratch-daily 2026-11-10 0; setc scratch-daily 2026-11-11 3
ev scratch-daily
fill scratch-daily 2026-11-10 2026-11-11 11
at "2026-11-18 13:02"; ev scratch-daily
check "both CLOSED" '[[ "$(gst scratch-daily 2026-11-10 state)" == CLOSED && "$(gst scratch-daily 2026-11-11 state)" == CLOSED ]]'
check "rows before/after recorded" '[[ "$(gst scratch-daily 2026-11-11 rows_before)" == 3 && "$(gst scratch-daily 2026-11-11 rows_after)" == 11 ]]'
check "one CLOSED ntfy with before -> after" '[[ "$(ntfy_n scratch-daily CLOSED)" == 1 ]] && grep -q "CLOSED - 2026-11-10 rows 0 -> 11, 2026-11-11 rows 3 -> 11" "$S/logs/ntfy.log"'
at "2026-11-18 13:04"; ev scratch-daily
check "no repeat CLOSED ntfy" '[[ "$(ntfy_n scratch-daily CLOSED)" == 1 ]]'
check "last_complete = 11-17" '[[ "$(jq -r .last_complete "$S/data/state/scratch-daily.json")" == 2026-11-17 ]]'

echo "D6 cache: complete periods are counted once per day (full scan), gaps every tick"
fresh; at "2026-11-18 13:00"
fill scratch-daily 2026-11-01 2026-11-17 12; setc scratch-daily 2026-11-12 0
ev scratch-daily; n1=$(wc -l < "$S/counts.log")
at "2026-11-18 13:02"; ev scratch-daily; n2=$(( $(wc -l < "$S/counts.log") - n1 ))
check "first tick counts all 14 ready periods" '[[ "$n1" -eq 14 ]]'
check "second tick counts only the open gap" '[[ "$n2" -eq 1 ]] && tail -1 "$S/counts.log" | grep -q "scratch-daily 2026-11-12"'
at "2026-11-19 13:00"; ev scratch-daily
check "next day: full re-scan (catches rows deleted after the fact)" '[[ "$(( $(wc -l < "$S/counts.log") - n1 - n2 ))" -ge 14 ]]'

echo "D7 weekly (ISO yearweek key, lag 7)"
fresh; at "2026-11-18 13:00"   # Wed of week 47; week 46 (anchor 11-09) is ready since Mon 11-16 07:00
for a in 2026-10-19 2026-10-26 2026-11-02 2026-11-09 2026-11-16; do setc scratch-weekly "$a" 500; done
setc scratch-weekly 2026-11-02 40
ev scratch-weekly
check "week of 11-02 short (40 < 100) -> OPEN" '[[ "$(gst scratch-weekly 2026-11-02 state)" == OPEN ]]'
check "current week 11-16 not judged (lag 7)" '[[ -z "$(gst scratch-weekly 2026-11-16 state)" ]] && ! grep -q "scratch-weekly 2026-11-16" "$S/counts.log"'
check "yearweek key is ISO %G%V" '[[ "$(WALKAWAY_DATA_NOW=$WALKAWAY_DATA_NOW bash "$ROOT/lib/data.sh" check scratch-weekly | jq -r ".periods[] | select(.period == \"2026-11-02\") | .key")" == 202645 ]]'

echo "D8 count errors: never judged as gaps; escalate once after N ticks"
fresh; at "2026-11-18 13:00"
echo '{"__error":"HTTP 503"}' > "$S/fx/scratch-daily.json"
export WALKAWAY_DATA_ERROR_TICKS=3
ev scratch-daily; ev scratch-daily
check "no gaps from errors" '[[ "$(jq -r ".gaps | length" "$S/data/state/scratch-daily.json")" == 0 ]]'
check "no ESCALATED before N" '[[ "$(ntfy_n scratch-daily ESCALATED)" == 0 ]]'
ev scratch-daily; ev scratch-daily
check "exactly one ESCALATED (priority high) at N" '[[ "$(ntfy_n scratch-daily ESCALATED)" == 1 ]] && grep "data scratch-daily: ESCALATED" "$S/logs/ntfy.log" | grep -q "	high	"'
unset WALKAWAY_DATA_ERROR_TICKS

echo "D9 REAL series.yaml + real incident counts (fixtures)"
fresh; export WALKAWAY_DATA_FILE="$ROOT/data/series.yaml"
# pulse_odds_snapshots 2026-10-15..10-18: 0 rows (real Throughline cron outage); 43 rows on the days around it
at "2026-10-19 09:00"; fill pulse-odds-snapshots 2026-10-04 2026-10-19 43; fill pulse-odds-snapshots 2026-10-15 2026-10-18 0
ev pulse-odds-snapshots
check "odds 10-15..10-18 OPEN (real outage)" 'grep -q "data pulse-odds-snapshots: OPEN - 2026-10-15..10-18 missing (0/22 rows)" "$S/logs/ntfy.log"'
# amazon_creator_connections_daily 2026-10-22: 1 row (real), floor 3
at "2026-10-25 12:00"; fill amz-creator-connections 2026-10-08 2026-10-23 7; setc amz-creator-connections 2026-10-22 1
ev amz-creator-connections
check "cc 10-22 short 1/3 OPEN (real short day)" '[[ "$(gst amz-creator-connections 2026-10-22 status)" == short && "$(gst amz-creator-connections 2026-10-22 rows_before)" == 1 ]]'
check "cc 10-23 (lag 2, ready 10-25 11:00) judged; 10-24 not" '[[ -z "$(gst amz-creator-connections 2026-10-24 state)" ]] && grep -q "amz-creator-connections 2026-10-23" "$S/counts.log" && ! grep -q "amz-creator-connections 2026-10-24" "$S/counts.log"'
# pulse_bb_showings_daily: 21/day through 11-08, nothing after (real, found in Phase 0)
at "2026-11-15 13:30"; fill bb-showings-daily 2026-10-25 2026-11-08 21
ev bb-showings-daily
check "bb 11-09..11-14 OPEN (real gap)" 'grep -q "data bb-showings-daily: OPEN - 2026-11-09..11-14 missing (0/10 rows)" "$S/logs/ntfy.log"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
(( FAIL == 0 ))

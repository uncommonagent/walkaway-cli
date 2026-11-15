# Data incident - drill-nopath - 2026-11-18

Written by the walkaway data operator (read-only) at 2026-11-15 12:23 ET.

## Gaps
- 2026-11-12: missing - rows 0 / floor 10 (rows when opened: 0); re-pull failed twice (command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh); last try: {"at":1795024881,"method":"command","label":"command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh","rc":0}

## Cause
The supervisor's re-pull cannot reach 2026-11-12 because scripts/pull.sh can only pull one date: scripts/pull.sh:17 sets `day=$(date -v-1d +%F)`, and the comment there says "always yesterday: there is no way to ask for another date". The script reads no arguments (usage line at scripts/pull.sh:4). Both re-pull attempts ran it on 2026-11-15 at 12:22:13 and 12:22:24 to fill 2026-11-12..2026-11-12. Both exited rc=0, but each one wrote yesterday's rows to fetch_day, not the gap date. That is why 2026-11-12 stayed at 0 rows (rows_before=0, rows_now=0, floor 10) while every neighbouring day has 12. The source can serve any past date: fetch_day takes a date in $1 (scripts/pull.sh:7, "the source API accepts any past date"). So the only missing piece is a way to pass a date range to the existing fetch_day path, which is the fix_hook contract. I found nothing that explains why the scheduled 06:00 run on 2026-11-13 missed 2026-11-12. The repo has a single commit (d64172e "daily pull") with no relevant history, and the evidence has no log from that run. The code has no error path that swallows a failure (`set -euo pipefail` is on), so most likely that run never happened or fell outside this code. The hook still closes the gap. A one-day miss like this will need the hook again whenever it recurs.

## Evidence
- check 2026-11-18 13:32 EST: period 2026-11-12 count=0 status=missing (floor 10); 2026-11-04..11-11 and 2026-11-13..11-17 count=12 status=ok
- state.gaps.2026-11-12: rows_before=0 rows_now=0 failed_tries=2 last_try rc=0 label 'command: bash .../scripts/pull.sh'
- repull_log [2026-11-15 12:22:13] fired command: bash .../scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
- repull_log [2026-11-15 12:22:24] fired command: bash .../scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
- scripts/pull.sh:17 day=$(date -v-1d +%F)   # always yesterday: there is no way to ask for another date
- scripts/pull.sh:4 Usage: scripts/pull.sh  no arguments: the date is always yesterday
- scripts/pull.sh:7-15 fetch_day() takes any YYYY-MM-DD and upserts s[d]=12 into $WALKAWAY_DATA_FIXTURES/drill-nopath.json
- series.repull[1] (requires_fix): bash .../scripts/pull.sh --from {from} --to {to}
- git log: only commit d64172e 'daily pull' (2026-11-15), so there is no recent change near 2026-11-12

## Decision
FIX BUILD fix-data-drill-nopath-20261118 (template v2 plan: /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/home/data-fixes/drill-nopath-2026-11-18/handoff/build-plan-fix-data-drill-nopath-20261118.md)
- confidence: high; protected_hit: false; needs_live_action: false

## Fresh read-only counts (2026-11-18 13:32 EST)
```json
[
  {
    "period": "2026-11-18",
    "key": "2026-11-18",
    "status": "not_ready",
    "count": null
  },
  {
    "period": "2026-11-17",
    "key": "2026-11-17",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-16",
    "key": "2026-11-16",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-15",
    "key": "2026-11-15",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-14",
    "key": "2026-11-14",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-13",
    "key": "2026-11-13",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-12",
    "key": "2026-11-12",
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-11",
    "key": "2026-11-11",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-10",
    "key": "2026-11-10",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-09",
    "key": "2026-11-09",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-08",
    "key": "2026-11-08",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-07",
    "key": "2026-11-07",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-06",
    "key": "2026-11-06",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-05",
    "key": "2026-11-05",
    "status": "ok",
    "count": 12
  },
  {
    "period": "2026-11-04",
    "key": "2026-11-04",
    "status": "ok",
    "count": 12
  }
]
```

## Re-pull log (supervisor)
```
[2026-11-15 12:22:11] drill-nopath: command bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh
[2026-11-15 12:22:13] drill-nopath: fired command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
[2026-11-15 12:22:23] drill-nopath: command bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh
[2026-11-15 12:22:24] drill-nopath: fired command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/home/data-fixes/drill-nopath-2026-11-18/handoff/evidence-drill-nopath-2026-11-18.json

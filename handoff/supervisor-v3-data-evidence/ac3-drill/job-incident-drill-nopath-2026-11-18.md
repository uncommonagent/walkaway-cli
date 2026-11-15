# Data incident - drill-nopath - 2026-11-18

Written by the walkaway data operator (read-only) at 2026-11-15 13:14 ET.

## Gaps
- 2026-11-12: missing - rows 0 / floor 10 (rows when opened: 0); re-pull failed twice (command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh); last try: {"at":1795024863,"method":"command","label":"command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh","rc":0}

## Cause
scripts/pull.sh can only pull yesterday. Line 18 runs `day=$(date -v-1d +%F)` and the script reads no arguments, so no code path can fetch 2026-11-12. The supervisor's re-pulls ran at 2026-11-15 13:13:55 and 13:14:06. Both exited rc=0, but each one fetched yesterday relative to its own run time (2026-11-14), not 2026-11-12, so 2026-11-12 stayed at 0 rows. That is why the gap shows "re-pull failed twice" even though the command succeeded. The fetch itself is not broken: fetch_day (pull.sh:7-15) accepts any past date, and the source API takes ?date=. The repo has one commit (b90ead3 "daily pull") with no logging, so it doesn't show why the scheduled 06:00 run on 2026-11-13 missed 2026-11-12. Every neighbouring day has 12 rows, which points to a single missed scheduled run, not a code defect in the fetch. The fix is the planned date-range hook, routed through the existing fetch_day. After it merges, the supervisor's second repull entry (`pull.sh --from {from} --to {to}`) closes the gap.

## Evidence
- check: 2026-11-12 count=0 status=missing (floor 10); 2026-11-04..11-11 and 2026-11-13..11-17 each count=12 status=ok
- repull_log: [2026-11-15 13:13:55] fired command: bash .../scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
- repull_log: [2026-11-15 13:14:06] fired command: bash .../scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
- state.gaps.2026-11-12: failed_tries=2, last_try.rc=0, rows_now=0 (command succeeded but pulled a different date)
- scripts/pull.sh:18 `day=$(date -v-1d +%F)   # always yesterday: there is no way to ask for another date`
- scripts/pull.sh:4 usage: no arguments, date is always yesterday; script ignores $@
- scripts/pull.sh:7-15 fetch_day($1=YYYY-MM-DD) is the existing fetch/upsert path and accepts any past date
- series.repull[1]: requires_fix=true, command `bash .../scripts/pull.sh --from {from} --to {to}`
- git log: single commit b90ead3 'daily pull' (2026-11-15); no history explaining the missed 2026-11-13 06:00 run

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
[2026-11-15 13:13:54] drill-nopath: command bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh
[2026-11-15 13:13:55] drill-nopath: fired command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
[2026-11-15 13:14:04] drill-nopath: command bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh
[2026-11-15 13:14:06] drill-nopath: fired command: bash /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/pull-drill/scripts/pull.sh for 2026-11-12..2026-11-12 (rows before: 2026-11-12=0)
```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/home/data-fixes/drill-nopath-2026-11-18/handoff/evidence-drill-nopath-2026-11-18.json

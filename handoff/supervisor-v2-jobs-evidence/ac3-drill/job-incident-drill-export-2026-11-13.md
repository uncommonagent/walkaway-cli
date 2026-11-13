# Job incident - drill-export - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:50 ET.

## Failure
not OK by 09:00: 3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)

## Cause
All 3 export_runs rows for 2026-11-13 (11:00:02Z, 11:30:03Z, 12:00:04Z) have ok=false, total=null and error "total is NaN (scripts/nightly-export.js:18)". The cause is a misspelled field name. total() at scripts/nightly-export.js:12 reads `r.ammount` (two m's), but readOrders (scripts/nightly-export.js:5-9) keys each row by the CSV header in data/orders.csv:1, which is `id,customer,amount`. So r.ammount is undefined for every row, parseFloat(undefined) returns NaN, the sum is NaN, and run() throws at scripts/nightly-export.js:17. The message in that throw says line 18, which is off by one. The bug is deterministic, so retrying cannot fix it: every attempt failed the same way. The code was added in the repo's only commit, 4a10a42 ("nightly export runner"), so there is no recent change to blame or revert. With the correct field, the expected total for the current data is 12.50 + 30.25 + 7.00 = 49.75.

## Evidence
- export_runs 2026-11-13T12:00:04Z ok=false total=null error="total is NaN (scripts/nightly-export.js:18)"
- export_runs 2026-11-13T11:30:03Z ok=false total=null error="total is NaN (scripts/nightly-export.js:18)"
- export_runs 2026-11-13T11:00:02Z ok=false total=null error="total is NaN (scripts/nightly-export.js:18)"
- state.failed_detail: "not OK by 09:00: 3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)"
- scripts/nightly-export.js:12 `return rows.reduce((sum, r) => sum + parseFloat(r.ammount), 0)`: misspelled key 'ammount'
- data/orders.csv:1 header `id,customer,amount`: the real key is 'amount'
- scripts/nightly-export.js:7-8: readOrders keys each row by the header columns, so r.ammount === undefined and parseFloat(undefined) is NaN
- scripts/nightly-export.js:17: the NaN guard throws, and its message names line 18 (off by one)
- git log: only commit 4a10a42 'nightly export runner' (2026-11-13 12:50 -0500) added the file with the typo already in it

## Decision
FIX BUILD fix-drill-export-20261113 (template v2 plan: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/drill-export-2026-11-13/handoff/build-plan-fix-drill-export-20261113.md)
- confidence: high; protected_hit: false; needs_live_action: false

## Check rows (read-only, 2026-11-13T14:01:14Z)
- query runs: `export_runs?select=started_at,ok,total,error&run_date=eq.2026-11-13&order=started_at.desc`

```json
{
  "verdict": "retrying",
  "detail": "3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)",
  "rows": {
    "runs": 3
  },
  "sample": {
    "runs": [
      {
        "started_at": "2026-11-13T12:00:04Z",
        "ok": false,
        "total": null,
        "error": "total is NaN (scripts/nightly-export.js:18)"
      },
      {
        "started_at": "2026-11-13T11:30:03Z",
        "ok": false,
        "total": null,
        "error": "total is NaN (scripts/nightly-export.js:18)"
      },
      {
        "started_at": "2026-11-13T11:00:02Z",
        "ok": false,
        "total": null,
        "error": "total is NaN (scripts/nightly-export.js:18)"
      }
    ]
  },
  "log": {}
}
```

## Diagnose rows
```json
{
  "queries": {},
  "rows": {},
  "logs": {}
}
```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/drill-export-2026-11-13/handoff/evidence-drill-export-2026-11-13.json

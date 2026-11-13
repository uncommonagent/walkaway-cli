# Job incident - drill-export - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:21 ET.

## Failure
not OK by 09:00: 3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)

## Cause
All 3 export_runs attempts on 2026-11-13 (11:00:02Z, 11:30:03Z, 12:00:04Z) failed with ok=false, total=null, error "total is NaN (scripts/nightly-export.js:18)". The cause is a misspelled field name. total() in scripts/nightly-export.js:12 reads `r.ammount` (double m). readOrders() at scripts/nightly-export.js:5-9 builds row objects keyed by the CSV header, and the header in data/orders.csv:1 is `id,customer,amount`. So every r.ammount is undefined, parseFloat(undefined) is NaN, and the sum is NaN. run() then throws at scripts/nightly-export.js:17 (the message says line 18, which is off by one). The code came in as a single commit (630d760 "nightly export runner"), so this is a code bug, not a data or transient problem. Retries cannot succeed without a code change, which matches all three attempts failing with the same error. The correct total for the current input is 12.50 + 30.25 + 7.00 = 49.75.

## Evidence
- export_runs 2026-11-13T12:00:04Z ok=false total=null error='total is NaN (scripts/nightly-export.js:18)'
- export_runs 2026-11-13T11:30:03Z ok=false total=null error='total is NaN (scripts/nightly-export.js:18)'
- export_runs 2026-11-13T11:00:02Z ok=false total=null error='total is NaN (scripts/nightly-export.js:18)'
- scripts/nightly-export.js:12  return rows.reduce((sum, r) => sum + parseFloat(r.ammount), 0)  -- typo 'ammount'
- data/orders.csv:1  id,customer,amount  -- real column is 'amount'
- scripts/nightly-export.js:8  readOrders keys rows by header columns, so r.ammount is undefined
- scripts/nightly-export.js:17  throws 'total is NaN (scripts/nightly-export.js:18)' (line reference in message is off by one)
- git log: only commit 630d760 'nightly export runner' introduced the runner and the CSV together; no later change

## Decision
FIX BUILD fix-drill-export-20261113 (template v2 plan: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/drill-export-2026-11-13/handoff/build-plan-fix-drill-export-20261113.md)
- confidence: high; protected_hit: false; needs_live_action: false

## Check rows (read-only, 2026-11-13T14:01:46Z)
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

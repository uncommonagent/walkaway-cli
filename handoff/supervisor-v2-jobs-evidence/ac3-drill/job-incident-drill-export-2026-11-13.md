# Job incident - drill-export - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 13:23 ET.

## Failure
not OK by 09:00: 3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)

## Cause
The job failed on all 3 attempts on 2026-11-13 (11:00:02Z, 11:30:03Z, 12:00:04Z), each with ok=false, total=null and error "total is NaN (scripts/nightly-export.js:18)". The cause is a misspelled field name. total() at scripts/nightly-export.js:12 sums parseFloat(r.ammount) with a double "m". readOrders() (scripts/nightly-export.js:5-9) builds row objects keyed by the CSV header, and data/orders.csv:1 is "id,customer,amount". So r.ammount is undefined, parseFloat(undefined) is NaN, the sum is NaN, and run() throws at scripts/nightly-export.js:17. The error text says ":18" but the throw is on line 17. This is deterministic, not transient: the code and the CSV were added together in the only commit (34a86c0 "nightly export runner"), so retries cannot succeed. The fix is to read the 'amount' field.

## Evidence
- export_runs 2026-11-13T12:00:04Z: ok=false, total=null, error='total is NaN (scripts/nightly-export.js:18)'
- export_runs 2026-11-13T11:30:03Z: ok=false, total=null, error='total is NaN (scripts/nightly-export.js:18)'
- export_runs 2026-11-13T11:00:02Z: ok=false, total=null, error='total is NaN (scripts/nightly-export.js:18)'
- state.failed_detail: 'not OK by 09:00: 3 failed attempt(s); latest 2026-11-13T12:00:04Z: total is NaN (scripts/nightly-export.js:18)'
- scripts/nightly-export.js:12: `return rows.reduce((sum, r) => sum + parseFloat(r.ammount), 0)`: field name misspelled 'ammount'
- scripts/nightly-export.js:7-8: row keys come from the CSV header columns
- data/orders.csv:1: header `id,customer,amount` (no 'ammount' column)
- data/orders.csv:2-4: amounts 12.50, 30.25, 7.00, so the expected total is 49.75
- scripts/nightly-export.js:17: NaN guard throws; the message says line 18, which is wrong (off by one)
- git log: only commit 34a86c0 'nightly export runner' added the runner and the CSV together, so the bug has been there since the start

## Decision
FIX BUILD fix-drill-export-20261113 (template v2 plan: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/drill-export-2026-11-13/handoff/build-plan-fix-drill-export-20261113.md)
- confidence: high; protected_hit: false; needs_live_action: false

## Check rows (read-only, 2026-11-13T14:01:28Z)
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

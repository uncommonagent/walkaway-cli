# Job incident - bf-daily - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:51 ET.

## Failure
not OK by 12:00: 3 failed attempt(s); latest 2026-11-13T12:43:36Z: BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)

## Cause
All three daily attempts (11:30Z, 12:06Z, 12:43Z) failed for the same two linked reasons, so this was not transient. (1) The Deals Hub export capture failed. pageDealsHubCapture (extension/bf-lists-lib.js:251-283) found and clicked #recentExportsButton, since the error is not the 'no Recent exports button' reason. But its XHR hook (line 264) never saw a /listDealsExports? request within 60x250ms, so it timed out at line 277. pullDealsExport (line 309) then returned 'deals hub capture: …'. Likely cause: Amazon changed the Deals Hub page, for example by sending the call through fetch() instead of XHR, renaming the request, or timing it differently. The hook only patches XMLHttpRequest. I can't confirm which change without a live, logged-in probe of the page. (2) The run fell back to the node scrape (line 366-378) and got only 39-45 deals. Node rows have no lowest_price_ytd/lowest_30d (line 245), so the 20% dealFloor (src/lib/bf-lists/build.ts:88-108, :179) and the lane filter left nothing. finalize returned an empty `after`, and createOne failed with 'no candidate is on deal on amazon.com right now' (bf-lists-lib.js:505). No daily draft exists (daily_list rows = []). A build plan for this exact incident is already committed: 7da72ae handoff/build-plan-bf-deals-ingest-fix.md, 08:20 ET today, not yet built (no feature/bf-deals-ingest-fix branch). That plan needs a live read-only probe in Audrey's logged-in Deals Hub session. Its AC3 also needs a live daily run that creates a draft list on Audrey's Amazon account, which is a protected list write. A second fix plan from me would duplicate it.

## Evidence
- bf_runs 2026-11-13T11:30:35Z ok=false summary.deals={live:45,rows:45,source:'node',error:'export: deals hub capture: listDealsExports call not seen in 15 s'} created=[{slug:'daily-2026-11-13',status:'failed',error:'no candidate is on deal on amazon.com right now'}]
- bf_runs 2026-11-13T12:06:37Z ok=false deals live 39 source node, same two errors
- bf_runs 2026-11-13T12:43:36Z ok=false deals live 39 source node, same two errors
- bf_lists list_date=2026-11-13: 0 rows (no daily draft)
- extension/bf-lists-lib.js:264 XHR-only hook matching /\/listDealsExports\?/
- extension/bf-lists-lib.js:277 timeout reason 'listDealsExports call not seen in 15 s'
- extension/bf-lists-lib.js:245 node-fallback deals have lowest_price_ytd/lowest_30d null
- extension/bf-lists-lib.js:366-378 node fallback path (source 'node', error 'export: …')
- extension/bf-lists-lib.js:505 'no candidate is on deal on amazon.com right now'
- src/lib/bf-lists/build.ts:88-108,179 dealFloor 20% applied to daily list
- git 7da72ae handoff/build-plan-bf-deals-ingest-fix.md: existing plan for this incident; AC3 requires a live daily run creating today's draft; no feature branch exists yet

## Decision
ESCALATED (protected action): Deals Hub export broke (all 3 runs fell back to 39-45 node deals, so no daily draft). bf-deals-ingest-fix is already planned, but it needs a live Deals Hub probe and a live draft create on Audrey's Amazon. Queue it: yes/no?
- confidence: medium; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:01:50Z)
- query runs: `bf_runs?select=started_at,finished_at,ok,line,error:summary->>error&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&kind=eq.daily&started_at=gte.2026-11-13T05:00:00Z&started_at=lt.2026-11-14T05:00:00Z&order=started_at.desc`

```json
{
  "verdict": "retrying",
  "detail": "3 failed attempt(s); latest 2026-11-13T12:43:36Z: BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
  "rows": {
    "runs": 3
  },
  "sample": {
    "runs": [
      {
        "started_at": "2026-11-13T12:43:36.305+00:00",
        "finished_at": "2026-11-13T12:50:53.273+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "error": null
      },
      {
        "started_at": "2026-11-13T12:06:37.261+00:00",
        "finished_at": "2026-11-13T12:13:56.593+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "error": null
      },
      {
        "started_at": "2026-11-13T11:30:35.732+00:00",
        "finished_at": "2026-11-13T11:39:05.22+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 45 (45 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "error": null
      }
    ]
  },
  "log": {}
}
```

## Diagnose rows
```json
{
  "queries": {
    "runs_full": "bf_runs?select=started_at,finished_at,ok,line,summary&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&kind=eq.daily&started_at=gte.2026-11-13T05:00:00Z&started_at=lt.2026-11-14T05:00:00Z&order=started_at.desc&limit=6",
    "daily_list": "bf_lists?select=slug,kind,state,error,list_date,drafted_at,updated_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&list_date=eq.2026-11-13"
  },
  "rows": {
    "runs_full": [
      {
        "started_at": "2026-11-13T12:43:36.305+00:00",
        "finished_at": "2026-11-13T12:50:53.273+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "summary": {
          "deals": {
            "live": 39,
            "rows": 39,
            "error": "export: deals hub capture: listDealsExports call not seen in 15 s",
            "source": "node",
            "export_id": null
          },
          "created": [
            {
              "slug": "daily-2026-11-13",
              "error": "no candidate is on deal on amazon.com right now",
              "status": "failed"
            }
          ],
          "renamed": [],
          "curations": [
            {
              "ok": true,
              "key": "early_bf",
              "ops": 0,
              "reason": null
            },
            {
              "ok": true,
              "key": "gift_guides",
              "ops": 0,
              "reason": null
            }
          ],
          "published": [],
          "refreshed": []
        }
      },
      {
        "started_at": "2026-11-13T12:06:37.261+00:00",
        "finished_at": "2026-11-13T12:13:56.593+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "summary": {
          "deals": {
            "live": 39,
            "rows": 39,
            "error": "export: deals hub capture: listDealsExports call not seen in 15 s",
            "source": "node",
            "export_id": null
          },
          "created": [
            {
              "slug": "daily-2026-11-13",
              "error": "no candidate is on deal on amazon.com right now",
              "status": "failed"
            }
          ],
          "renamed": [],
          "curations": [
            {
              "ok": true,
              "key": "early_bf",
              "ops": 0,
              "reason": null
            },
            {
              "ok": true,
              "key": "gift_guides",
              "ops": 0,
              "reason": null
            }
          ],
          "published": [],
          "refreshed": []
        }
      },
      {
        "started_at": "2026-11-13T11:30:35.732+00:00",
        "finished_at": "2026-11-13T11:39:05.22+00:00",
        "ok": false,
        "line": "BF lists daily 11/13: FAILED | deals 45 (45 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)",
        "summary": {
          "deals": {
            "live": 45,
            "rows": 45,
            "error": "export: deals hub capture: listDealsExports call not seen in 15 s",
            "source": "node",
            "export_id": null
          },
          "created": [
            {
              "slug": "daily-2026-11-13",
              "error": "no candidate is on deal on amazon.com right now",
              "status": "failed"
            }
          ],
          "renamed": [],
          "curations": [
            {
              "ok": true,
              "key": "early_bf",
              "ops": 0,
              "reason": null
            },
            {
              "ok": true,
              "key": "gift_guides",
              "ops": 0,
              "reason": null
            }
          ],
          "published": [],
          "refreshed": []
        }
      }
    ],
    "daily_list": []
  },
  "logs": {}
}
```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/bf-daily-2026-11-13/handoff/evidence-bf-daily-2026-11-13.json

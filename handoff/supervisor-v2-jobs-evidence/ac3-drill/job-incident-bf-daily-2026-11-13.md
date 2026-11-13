# Job incident - bf-daily - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 13:24 ET.

## Failure
not OK by 12:00: 3 failed attempt(s); latest 2026-11-13T12:43:36Z: BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)

## Cause
All 3 daily attempts on 11/13 (11:30, 12:06, 12:43 UTC) failed the same way. First, the Deals Hub export capture timed out. pageDealsHubCapture (extension/bf-lists-lib.js:250-283) clicks #recentExportsButton and waits for an XMLHttpRequest to /listDealsExports. That request was never seen, so the code returned 'listDealsExports call not seen in 15 s' (line 277). The deals ingest then fell back to the node scrape (ingestDeals, lines 364-378), which found only 39-45 deals. Node tiles carry no lowest_price_ytd or lowest_30d (dealFromNodeTile, line 245), so dealFloor (src/lib/bf-lists/build.ts:88-108) can only check them against list price. After poolFor's lane filter and the 20% deal floor (build.ts:179, added in #27 on 11/12), nothing was left. createOne then reported 'no candidate is on deal on amazon.com right now' (bf-lists-lib.js:505) and no daily-2026-11-13 row exists in bf_lists. The capture code has not changed since #25 (git log on extension/bf-lists-lib.js; #27 did not touch pageDealsHubCapture), and the export worked on 11/12. So the trigger is a change on Amazon's Deals Hub page, for example the page now using fetch instead of XHR, or the Recent exports flow changing. Which change it is can only be confirmed by probing the live Deals Hub page in Audrey's logged-in session. Proving any fix also needs a live daily run that writes a draft to Audrey's Amazon account. That is a protected live write, so I am escalating rather than queuing a fix. A build plan for this exact incident already exists: handoff/build-plan-bf-deals-ingest-fix.md (commit 7da72ae, 08:20 ET today). Its step 0 is that live probe and its step 3 runs the daily live.

## Evidence
- bf_runs 2026-11-13T11:30:35Z ok=false: deals 45 live, source node, deals.error='export: deals hub capture: listDealsExports call not seen in 15 s', created daily-2026-11-13 failed 'no candidate is on deal on amazon.com right now'
- bf_runs 2026-11-13T12:06:37Z ok=false: same, deals 39 live from node, same capture error and same create failure
- bf_runs 2026-11-13T12:43:36Z ok=false: same, deals 39 live from node, export_id null
- bf_lists list_date=2026-11-13: [] (no daily draft row)
- extension/bf-lists-lib.js:264: the hook watches XMLHttpRequest only, for /listDealsExports?
- extension/bf-lists-lib.js:277: timeout after 60x250ms with reason 'listDealsExports call not seen in 15 s'
- extension/bf-lists-lib.js:364-378 ingestDeals: node fallback, scrapeNodes(CANDIDATE_NODES, 2), discount>=30 and rating>=4.2 filter
- extension/bf-lists-lib.js:245 dealFromNodeTile: lowest_price_ytd and lowest_30d are null
- src/lib/bf-lists/build.ts:179 poolFor: lane filter plus dealFloor(d).ok for the daily list (added in 6902668, #27, 11/12 16:52)
- extension/bf-lists-lib.js:505 createOne: empty fin.after gives the 'no candidate is on deal' error
- git log -- extension/bf-lists-lib.js: capture code unchanged since 0944eff (#25), when the export worked (11/12: 29,148 live deals per the build plan)
- handoff/build-plan-bf-deals-ingest-fix.md (7da72ae): an existing plan for this incident, including a live Deals Hub probe (step 0) and a live daily draft run (step 3)

## Decision
ESCALATED (protected action): The Deals Hub export broke (Amazon page change) and the bf-deals-ingest-fix plan (7da72ae) is already written; may its builder probe Deals Hub live and run the daily to create today's draft on Audrey's account: yes or hold?
- confidence: medium; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:01:59Z)
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

# Job incident - bf-daily - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:21 ET.

## Failure
not OK by 12:00: 3 failed attempt(s); latest 2026-11-13T12:43:36Z: BF lists daily 11/13: FAILED | deals 39 (39 live) from node | drafts 0/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok | errors: export: deals hub capture: listDealsExports call not seen in 15 s (+1)

## Cause
All 3 daily attempts on 11/13 failed the same way, so this is not transient. First, the Deals Hub export capture timed out. pageDealsHubCapture (extension/bf-lists-lib.js:252-283) clicks #recentExportsButton and waits for an XHR whose URL matches /listDealsExports?/. That XHR never came, so the run hit 'listDealsExports call not seen in 15 s' at bf-lists-lib.js:277. The button itself was found; a missing button gives a different error at :267. This capture code has not changed since PR #25 (0944eff), and the export path worked on 11/12 (29,148 deals). So Amazon's Deals Hub page most likely changed today: perhaps it now uses fetch instead of XHR, uses a different request name, or adds a click step. I can't confirm which from the code. It takes a read-only probe of the logged-in Associates Deals Hub page. Second, ingest fell back to node tiles and got only 39-45 deals. After the lane filter and the 20% deal floor added yesterday in #27 (build.ts:88-110, used at build.ts:179), no daily candidate was left. createOne then failed with 'no candidate is on deal on amazon.com right now' (bf-lists-lib.js:505), and runDaily marked the run ok=false. A build plan for exactly this incident already exists: handoff/build-plan-bf-deals-ingest-fix.md, commit 7da72ae, 08:20 ET today. It covers a Phase 0 live Deals Hub probe, a capture fix, a stronger fallback and a live daily run. I'm escalating rather than queuing a second fix build, for two reasons. The cause is not pinned in code. And proving the fix needs live actions in Audrey's logged-in Amazon session: the probe, a live daily run that writes a draft to her list account, and an extension reload on the Mini.

## Evidence
- bf_runs 2026-11-13T11:30:35.732Z ok=false: deals 45 live, source node, export_id null, deals.error 'export: deals hub capture: listDealsExports call not seen in 15 s'; created daily-2026-11-13 failed 'no candidate is on deal on amazon.com right now'
- bf_runs 2026-11-13T12:06:37.261Z ok=false: deals 39 live, source node; same two errors
- bf_runs 2026-11-13T12:43:36.305Z ok=false: deals 39 live, source node; same two errors
- bf_lists for list_date 2026-11-13: no rows returned (daily_list = [])
- extension/bf-lists-lib.js:264 hooks XMLHttpRequest only, matching /listDealsExports?/; :266-268 clicks #recentExportsButton; :277 times out after 60x250ms with 'listDealsExports call not seen in 15 s'
- extension/bf-lists-lib.js:306-309 pullDealsExport returns 'deals hub capture: ...', after which ingest falls back to node tiles (dealFromNodeTile :239-248)
- extension/bf-lists-lib.js:505 createOne fails with 'no candidate is on deal on amazon.com right now' when finalize returns no ASINs
- src/lib/bf-lists/build.ts:88-110 dealFloor (20% floor) and :179 lane+floor filter for the daily list, added in 6902668 (#27, 2026-11-12 16:52 ET)
- git log on extension/bf-lists-lib.js: capture code unchanged since 0944eff (#25), whose export path ingested 29,148 deals on 11/12
- handoff/build-plan-bf-deals-ingest-fix.md (7da72ae, 2026-11-13 08:20 ET): an existing plan for this incident. It includes a Phase 0 live probe, a capture fix, a fallback threshold (>=120 full / 12-119 partial / <12 fail), a live daily run, and an extension reload on the Mini

## Decision
ESCALATED (protected action): A fix plan for this failure already exists (bf-deals-ingest-fix, 08:20 today), and it needs a live Deals Hub probe plus a live daily draft run in Audrey's account: run that plan, or no build today?
- confidence: medium; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:01:17Z)
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

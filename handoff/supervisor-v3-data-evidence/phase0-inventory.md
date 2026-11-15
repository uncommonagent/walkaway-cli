# Phase 0 inventory - supervisor-v3-data (2026-11-15, read-only)

Every scheduled pull / cron / launchd agent in both owner repos, discovered from code (file:line below) and
confirmed against live Supabase rows (REST GETs with the service-role key read from each repo's `.env.local` at
call time; never printed). No writes, no triggers. The machine-readable id list is `phase0-inventory.txt`;
`data/series.yaml` must name every id (watched or excluded with a reason): that diff is AC1.

Repos: Showrunner = `~/Projects/audrey-ops-platform` (source `audrey`, user `d3a83609-...`), Throughline =
`~/Projects/Throughline/throughline-app` (source `throughline`, pulse team `d14dce4f-...`).

## Floors (formula, applied to every watched series)
30-day (daily) / 8-week (weekly) per-period row counts over the periods present (`phase0-floors.tsv`):
- every period has the same count c -> floor = c ("structural": e.g. one ST total row per day, 2 connect programs);
- otherwise floor = max(1, floor(median / 2)) (the plan's "rows >= 50% of 30-day median").
Monthly `pulse-member-snapshots`: 10082 / 10131 / 10161 rows on 09-01 / 10-01 / 11-01 -> floor 5040.

## Landing times (ready_by calibration, real rows)
| series | period D lands (ET) | evidence row |
|---|---|---|
| amz-tracking-offsite | D+1 ~08:00 | date 11-13 created 2026-11-14T12:59:48Z |
| amz-creator-connections / spc | D+2 ~07:40 | cc 11-12 created 11-14T12:39:58Z, spc 11-14T12:43:18Z |
| amz-connect-summary | D ~07:20 (rolling 35-day window, re-upserted twice a day) | 11-13 created 11-13T12:22:11Z |
| markable-spend | D+1 ~07:00 | 11-13 created 11-14T11:59:50Z |
| meta-daily-metrics | D+1 07:00 (cron 12:00 UTC, delete+insert of the span) | 11-13 re-inserted 11-15T12:00:26Z |
| st-showings-daily | D+1 06:00-06:45 (+ 09:30 / 12:30 failed-date retries) | v2 evidence: 11-12 first seen 11-13T11:45:43Z |
| bb-showings-daily | D+1 ~06:20 (after ST terminal) | 11-08 captured 11-09T11:20:20Z |
| st-showings-forward | D ~06:40 (after ST) | 11-14 captured 11-14T11:39:01Z |
| pulse-daily-snapshots | D+1 ~02:36 (cron 07:30 UTC; ifMissing 10:00 UTC) | 11-14 created 11-15T07:36:12Z |
| pulse-odds-snapshots | D ~05:00 (cron 10:00 UTC) | 11-14 created 11-14T10:00:58Z |
| pulse-events-refresh | D ~05:01 (cron 10:00 UTC) | ran_at 11-15T10:01:05Z |
| pulse-weekly-stats / signal / market-health | rewritten nightly; week W final the Monday after | 202645 computed 11-15T07:36Z / 09:02Z |
| tma-cohort-showings / pulse-showings-weekly / recap-reports | Monday W+1 ~06:10-06:30 | 202645 computed 11-09T11:28Z; weekly uploaded 11-09T11:09Z |
| curb-inquiry-results | Monday M ~05:30 (week_date = M) | 11-09 scanned 11-09T10:30:54Z |

## Watched series (dated rows, gap detection on)
| id | owner | schedule (code) | table.key (filters) | cadence | lag / ready_by | floor | re-pull (existing path) | source re-pulls past dates? |
|---|---|---|---|---|---|---|---|---|
| amz-tracking-offsite | SR | extension morning 07-10 ET, poll `src/app/(app)/api/integrations/extension/poll/route.ts:11-12,180-207` | amazon_tracking_daily.date (store_id=offsite) | daily | D+1 11:00 | 13 (50% of 27) | age 1: run-now (`extension_report_state.run_now_requested_at`, poll:95-145 pulls yesterday); age 2-8: extension self-heal (`/api/ingest/amazon/missing` + `extension/heal-lib.js`, automatic) | yes, Custom Date Range (`heal-lib.js:15-75`) |
| amz-tracking-onsite | SR | same, runs last (`extension/background.js:520`) | amazon_tracking_daily.date (store_id=onsite) | daily | D+1 11:00 | 2 (structural) | same as offsite | yes |
| amz-creator-connections | SR | morning D-2 / evening D-1 (poll:202-203,235) | amazon_creator_connections_daily.date | daily | D+2 11:00 | 3 (50% of 7) | run-now `cc`: before 12:00 pulls D-2, after pulls D-1 (poll:129-133). No self-heal (`missing/route.ts:98` CC_HEAL_ENABLED) | yes, fromDate/toDate (`connect-runner.js:495-530`) |
| amz-sponsored-products | SR | same as cc | amazon_sponsored_products_daily.date | daily | D+2 11:00 | 38 (50% of 77) | run-now `spc` (as cc) + self-heal ages 2-8 | yes |
| amz-connect-summary | SR | morning + evening, rolling 35-day window (`background.js:572`, `connect-runner.js:280-289`) | amazon_connect_summary_daily.date | daily | D+1 11:00 | 2 (structural) | self-heal: every run re-pulls the last 35 days | yes (`connect-runner.js:257-265`) |
| markable-spend | SR | extension 07:00 + 20:00 (`config.js:21-30`, `background.js:294-335`) | markable_spend_daily.report_date | daily | D+1 09:00 | 1 (structural) | self-heal: every run re-pulls month-to-date (prior month when day <= 10, `markable-lib.js:64-77`) | yes |
| meta-daily-metrics | SR | Vercel cron 12:00 UTC `/api/cron/meta-sync` (`vercel.json`) | meta_daily_metrics.date | daily | D+1 09:00 | 1 (50% of 3) | GET `https://audrey-ops-platform.vercel.app/api/cron/meta-sync` (Bearer CRON_SECRET, `cron/meta-sync/route.ts:11-17`) re-pulls latest-3..yesterday (`meta-sync.ts:136-162`) | yes (time_range) |
| st-showings-daily | TL | extension 06:00-06:45 + 07:00 login retry + 09:30/12:30 failed-date retries (`tools/showings-daily-pull/pull-core.js:307-317,420`, `background.js:101-201`) | pulse_showings_daily.obs_date (is_total=true) | daily | D+1 12:45 | 1 (structural) | `open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily"` pulls D-1..D-8 (`background.js:89-99`, `pull-core.js:70-75`) | yes (FromDate/ToDate, `pull-core.js:80-93`); trigger takes no date |
| bb-showings-daily | TL | extension, after ST terminal (`bb-core.js:611-612`) | pulse_bb_showings_daily.obs_date (is_total=true) | daily | D+1 13:00 | 10 (50% of 21) | age 1: the ST URL trigger (it calls `setBbPending(true)`, `background.js:95`, so BB pulls yesterday after ST). Ages 2+: **none scriptable**: popup `START_BB_BACKFILL {days}` only (`bb-core.js:955-993`); no external messaging (no externally_connectable) | yes, up to 90 days |
| st-showings-forward | TL | extension, after ST daily | pulse_showings_forward.snapshot_date (is_total=true) | daily | D 13:00 | 4 (structural) | none | **no**: as-of snapshot of the forward book |
| pulse-daily-snapshots | TL | Vercel cron `30 7 * * *` + `?ifMissing=1` `0 10 * * *` | pulse_daily_snapshots.snapshot_date (team, geo_type=central_oh) | daily | D+1 07:00 | 1 (structural) | age 1: GET `https://throughlinepro.com/api/cron/pulse-daily-sync?ifMissing=1` (Bearer CRON_SECRET, route.ts:41-60); older: `POST /api/admin/pulse-backfill` (HMAC, not wired - operator) | partial: backfill recomputes from listing intervals |
| pulse-odds-snapshots | TL | Vercel cron pulse-macro `0 10 * * *` | pulse_odds_snapshots.snapshot_date | daily | D 08:00 | 43 (structural) | age 0: GET `/api/cron/pulse-macro` | **no**: as-of today |
| pulse-events-refresh | TL | Vercel cron `0 10 * * *` | pulse_events_refresh_runs.ran_at (timestamp, UTC day) | daily | D 08:00 | 1 (structural) | age 0: GET `/api/cron/pulse-events-refresh` | n/a (run ledger: only today can be re-run) |
| pulse-weekly-stats | TL | written by pulse-daily-sync nightly | pulse_weekly_stats.year_week (team, central_oh) | weekly | Mon after 07:00 | 1 (structural) | none (rollup of the daily sync; pulse-backfill for history) | partial (backfill) |
| pulse-signal-scores | TL | Vercel cron `0 9 * * *` (current + 6 trailing weeks) | pulse_signal_scores.year_week (team) | weekly | Mon after 07:00 | 264 (50% of 528) | weeks 0-6: GET `/api/cron/pulse-signals` | yes (trailing 6 / `?scope=full`) |
| pulse-market-health | TL | Vercel cron `30 9 * * *` | pulse_market_health_weekly.year_week (team) | weekly | Mon after 07:00 | 264 (50% of 529) | weeks 0-6: GET `/api/cron/pulse-market-health` | yes |
| tma-cohort-showings | TL | extension Mondays after ST (`tma-core.js:40,330-336`) | recap_cohort_showings.year_week (team) | weekly | Mon after 13:00 | 256 (50% of 512) | self-heal: the manifest re-adds missing weeks of the last 13 on the next Monday (`lib/showingtime/tma-manifest.ts:100-108,204`) | yes (13 weeks) |
| pulse-showings-weekly | TL | daily-ingest weekly rollup (`daily-ingest/route.ts:89-110`) | pulse_showings_weekly.year_week (team) | weekly | Mon after 13:00 | 1 (structural) | none (rebuilt when a daily ingest of that week lands) | yes via ST |
| recap-reports | TL | extension Mondays after ST+BB (`recap-core.js:63,586-591`) | report_pdfs.received_at (team, received_from_email=recap-extension@showingtime.local), ET week | weekly | Mon 13:00 | 15 (50% of 31) | none (popup `START_RECAP`) | unknown |
| curb-inquiry-results | TL | Vercel cron `30 10 * * 1` | curb_inquiry_results.week_date (team; = scan Monday) | weekly | Mon 08:00 | 1 (50% of 2) | none | no (trailing 7 days as of the scan) |
| pulse-member-snapshots | TL | Vercel cron `0 6 1 * *` | pulse_member_snapshots.snapshot_date (team; = 1st) | monthly | 1st 08:00 | 5040 (50% of 10131) | none | **no**: live roster |

## Excluded (listed in series.yaml with `watch: false` + reason; no gap detection)
| id | why not a data series | covered by |
|---|---|---|
| amz-tracking-offsite-today | evening intra-day pull of D into the same rows; replaced by the D+1 morning pull (`amazon-ingest.ts:24-31`) | amz-tracking-offsite |
| amz-bounties | a "No data found" day writes NO rows by design (`ingest/amazon/route.ts:158-183`): 6 row-days in 30, so a missing day is indistinguishable from zero bounties | jobs.yaml extension-reports (bounty success within 26 h) |
| amz-self-heal | the extension's repair loop, not a pull of its own | it is the re-pull path of tracking/spc |
| sr-daily-digest, sr-evening-digest | Vercel crons that send emails (evening also writes derived `ordered_preview_log` only when ordered > 0) | - (sends; PROTECTED) |
| idea-list-asin-stats | manual popup refresh, no scheduler (`background.js:1610`), one row per ASIN, not dated | - |
| cc-optin-am, cc-optin-pm, spc-optin, bf-daily | live actions, not data pulls | jobs.yaml |
| st-session-state | `st_session_attempts` is an attempt ledger (table only since 11-13) | jobs.yaml showingtime |
| st-listing-refresh | 2-minute single-listing job queue | - |
| pulse-macro-series | release-driven observations (FRED etc.), no per-day expectation | the same cron's daily run is watched by pulse-odds-snapshots |
| pulse-revision-sweep, pulse-reconcile, showingtime-maintenance | repair / maintenance crons | - |
| pulse-events | Monday reminder send | - |
| daily-pulse-brief | send (one `pulse_brief_sends` row per sent day) | - (PROTECTED send) |
| recap-offer-sync, offer-inbox-scan, gmail-poll, field-guide-dispatch | inbox / queue scans, rows depend on incoming mail | - |
| monday-autorun, monday-fallback, substack-publisher, st-login-agent | newsletter generation/publish and the ST login agent | jobs.yaml realtea-generate / realtea-publish / showingtime |
| offer-tracker | launchd plist in repo, not installed in ~/Library/LaunchAgents | - |
| inngest-unregistered | `pulse-nightly`, `pulse-macro`, `pulse-events`, `spark-sync` exist in inngest/functions but are not registered (`app/api/inngest/route.ts` serves only mondayAutorun) | - |

Not found: the plan's "linked_product orders" has no scheduled pull in the Showrunner code (no route, alarm or
table); nothing to watch.

## Real gaps already visible (input to AC4)
- **bb-showings-daily: no rows after obs_date 2026-11-08** (11-09..11-14 missing, 6 periods in the 14-day lookback).
  BrokerBay can re-pull 90 days, but only from the popup: 11-14 (age 1) can be re-pulled by the ST URL trigger,
  11-09..11-13 have no scriptable re-pull path -> data operator.
- Outside the lookback (real fixtures for tests): 2026-10-15..10-18 missing in pulse_odds_snapshots,
  pulse_events_refresh_runs, pulse_brief_sends, pulse_showings_forward (a 4-day Throughline cron/extension gap);
  amz-creator-connections 2026-10-22 = 1 row (short vs floor 3).

## Re-pull guards (plan item 2)
- Amazon (all `amz-*` triggers): business hours 09:00-19:00 ET = Showrunner's own `BUSINESS_HOURS`
  (`extension/cc-optin-lib.js:53`); never while a CC batch is in flight = today's `cc_optin_runs` status PLANNED or
  RUNNING, or any `cc_optin_batches` row SUBMITTED (`20261024000001_cc_optin.sql:9-11`); paced: one Amazon trigger
  per 15 minutes across all series.
- Max 2 tries per gap per day; a try counts only when a trigger fired (a guard deferral is not a try).
- A RE-PULL of data is never protected (Jim 11/15). The run-now trigger writes only
  `extension_report_state.run_now_requested_at` for one base report type (what the Showrunner run-now route itself
  sets); the HTTP triggers are the routes' own cron GETs; the ST trigger is the URL the ST login agent opens.

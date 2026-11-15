# Walkaway Build Plan: supervisor-v3-data

## Feature name
`supervisor-v3-data`

## Branch name
`feature/supervisor-v3-data`

## Goal
No data loss from any scheduled extension pull or ingest cron in Showrunner or Throughline. The supervisor watches
every dated data series (not just "did the job run today"), detects missing or short days, re-pulls them through the
job's own pull path, verifies the rows landed, and launches a fix build when a re-pull cannot succeed. Jim hears one
ntfy line per gap found and one per gap closed.

## Evidence (Claude, 11/15)
- jobs.yaml (v2) covers: bf-daily, cc-optin-am/pm, spc, extension-reports (aggregate "succeeded within 26 h"),
  showingtime, realtea-generate/publish. It checks today's run, not historical gaps, and has no re-pull/backfill.
- Not covered:
  - Throughline extension tools/showings-daily-pull: ST daily pull (+ retry + failed-dates retry alarms), BrokerBay
    (bb-core.js), TMA (tma-core.js), recap (recap-core.js), ST single-listing refresh poll.
  - Throughline Vercel crons (vercel.json): pulse-daily-sync (+ ifMissing), pulse-signals, pulse-market-health,
    pulse-revision-sweep, pulse-macro, pulse-events(+refresh), pulse-member-snapshot, daily-pulse-brief,
    showingtime-maintenance, recap-offer-sync, offer-inbox-scan, gmail-poll, curb-inquiry-scan,
    field-guide-dispatch.
  - Showrunner extension report types individually: tracking_offsite, tracking_offsite_today, tracking_onsite, cc
    (morning/evening), spc (morning/evening), connect_summary (morning/evening), bounty, linked_product orders.
- 11/14: tracking_offsite failed 07:07 and recovered on retry; a day that never recovers today leaves a silent hole.

## Decisions
Jim 11/15: monitor every Showrunner + Throughline daily extension run; Claude launches fixes and re-pulls so there is
no data loss. Protected actions unchanged (CC/SPC opt-ins, Substack publish, list publishes, spend, credentials,
deletes) - those still escalate; a RE-PULL of data is never protected.

## Quality rules
Protocol merge-gate standard; every series check is proven against real rows.

## Source of truth
Each series' own table (both Supabase projects): e.g. amazon_tracking_daily, amazon_creator_connections_daily,
amazon_sponsored_products_daily, amazon_connect_summary_daily, amazon_bounties_daily, idea_list_asin_stats,
pulse_showings_daily, BrokerBay/TMA/recap tables (Phase 0 finds them), pulse_* tables, extension_report_state,
st session-state table; Vercel cron logs for cron jobs.

## What to build
0. Phase 0 inventory (read-only): every scheduled pull/cron in both repos -> data/series.yaml entries: name, owner
   repo, schedule, the table + date column it writes, expected cadence (daily / weekday / weekly), expected row
   floor (from the last 30 days' median, e.g. ST total showings row = 1/day; tracking_offsite rows >= 50% of 30-day
   median), lag (data for D lands on D+1), re-pull method (extension run-now with date range, cron URL with date
   param, Inngest event), and whether the source allows historical re-pulls (Amazon reports: yes by date; ST: yes by
   date; BrokerBay/TMA: Phase 0 states). Archive one real passing check per series.
1. Gap detector (every supervisor tick, 14-day lookback): for each series, dates with missing rows or rows under
   the floor, past their own retry window -> GAP. States per gap: OPEN, REPULLING, CLOSED, FIXING, ESCALATED.
2. Re-pull: trigger the series' own re-pull for exactly the gap dates (paced, business hours for Amazon, never
   during a CC batch, max 2 tries per gap per day), then verify rows landed at/above the floor -> CLOSED.
   Uses only existing pull paths; adds date-range run-now hooks where a job lacks one (owner repo change, via a fix
   build).
3. If re-pull fails twice or no re-pull path exists: operator writes job-incident file and a template-v2 fix plan in
   the owner repo (one builder per repo, queue if busy). After merge, re-pull every open gap date for that series and
   confirm CLOSED.
4. ntfy: one line on gap OPEN (series, dates), one on CLOSED (rows landed), one on ESCALATED with one question.
   09/13/17 heartbeat lists open gaps only.
5. `walkaway status` gets a DATA table: series, last complete date, open gaps, last action.

## Do NOT build
No changes to how pulls work except adding date-range run-now hooks via fix builds. No dashboards. No protected
actions.

## Acceptance criteria
- [ ] AC1 series.yaml covers every scheduled pull/cron found in Phase 0 (inventory list vs yaml diff = 0), each with
      a real passing check dumped.
- [ ] AC2 Tests: gap detection (missing, short, lag-aware, weekday cadence), retry window respected, re-pull cap,
      escalation on no re-pull path.
- [ ] AC3 Drill on a scratch series: delete-free simulation (fixture rows) -> OPEN -> re-pull stub -> CLOSED; failing
      re-pull -> fix plan queued; exactly one ntfy per transition (drill topic).
- [ ] AC4 Live: run the detector over the real last 14 days, archive the gap report; any real gaps found are
      re-pulled and closed (or escalated with reason). Evidence per gap: rows before/after.
- [ ] AC5 Supervisor reloaded; `walkaway status` shows JOBS + DATA tables (archived). shellcheck 0, tests green.

## Gate checklist
Diff inventory vs series.yaml; open the 14-day gap report and the before/after rows for each closed gap; count drill
ntfy lines per transition.

## Stop rules
Never delete or overwrite existing rows to "test". Never trigger CC/SPC opt-ins or any publish. Amazon re-pulls only
in business hours and never while a CC batch is in flight.

## Escalate to Jim
Any re-pull that would need credentials, spend, or a protected action; any series whose source cannot re-pull a past
date (state which dates are lost).

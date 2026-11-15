# Live re-pull: bb-showings-daily 2026-11-14 (2026-11-15, Mac mini, data watching ON)

Series: bb-showings-daily. Table pulse_bb_showings_daily.obs_date (is_total=true), floor 10, ready at D+1 13:00 ET.
Re-pull method for age 1: the series' own scheduled path, the extension daily run (`#tl-ext-run-daily`, ST then BB).
Guard `st_brief_sent` passed: today's brief had already gone out, so the ST step cannot fire a send.

## Timeline (supervisor-data-lines-final.log, data-repull.log, ntfy-live-data-lines-final.log)
| Time (ET) | Event |
|---|---|
| 13:01:32 | `2026-11-14 -> OPEN - 2026-11-14 missing (0/10 rows)` and one ntfy (default priority) |
| 13:01:34 | try 1 fired: `open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily" for 2026-11-14..2026-11-14 (rows before: 2026-11-14=0)`, then REPULLING, verify 13:46 |
| 13:47:30 | `try failed (rows below floor at verify)`: 0 rows |
| 13:47:31 | try 2 fired (same command, rows before 0), verify 14:32 |
| 14:33:25 | `try failed (rows below floor at verify)` -> failed_tries 2 -> data operator |
| 14:34:33 | ESCALATED, one ntfy (priority high): "On the Mini's Chrome, is edge.brokerbay.com signed in? (BB has written no rows since 11-10. If it's logged out, sign in once and I'll queue the date-range repull hook to backfill 11-09 to 11-14.)" |

REPULLING sent no ntfy, as designed. The P2 fix (verify needs a good count) held live. The 14:33 verify used a
count taken at the same tick (`counted_at` 1794771336 >= `verify_at` 1794771150).

## Rows before/after (exact count, read-only; bb-check-1436.json, 14:36 ET)
| obs_date | before (12:22 / 13:01) | after (14:36) | state |
|---|---|---|---|
| 2026-11-08 | 21 | 21 | ok (last complete) |
| 2026-11-09 | 0 | 0 | ESCALATED |
| 2026-11-10 | 0 | 0 | ESCALATED |
| 2026-11-11 | 0 | 0 | ESCALATED |
| 2026-11-12 | 0 | 0 | ESCALATED |
| 2026-11-13 | 0 | 0 | ESCALATED |
| 2026-11-14 | 0 | 0 | ESCALATED (2 failed tries) |

## Why it is escalated, not closed
`job-incident-bb-showings-daily-2026-11-15-final.md` (the operator's second diagnosis, confidence medium,
protected_hit true):
- ShowingTime lands every day.
- The BB step has written nothing since the 11-10 morning run, which pulls obs date 11-09.
- No extension code changed around 11-09/11-10.
- Most likely cause: an expired BrokerBay SSO session. `runBbJobInner` returns needsLogin (bb-core.js:909-911), and
  `maybeRunBbAfterSt` discards it (background.js:229).

A date-range hook would fail the same way until someone signs in again. A sign-in is a credential/protected action,
so the plan's "Escalate to Jim" rule applies. The dates are NOT lost: BrokerBay re-pulls up to 90 days. After the
sign-in, the operator queues the `#tl-ext-repull=bb` fix build (the fix_hook in data/series.yaml), and the supervisor
re-pulls 11-09..11-14 as one range.

Files: `state-bb-showings-daily-final.json`, `evidence-bb-showings-daily-2026-11-15.json` (the operator's evidence
bundle), `job-incident-bb-showings-daily-2026-11-15-final.md`, `supervisor-data-lines-final.log`,
`ntfy-live-data-lines-final.log`, `bb-check-1436.json`.

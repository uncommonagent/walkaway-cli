# Data incident - bb-showings-daily - 2026-11-15

Written by the walkaway data operator (read-only) at 2026-11-15 14:34 ET.

## Gaps
- 2026-11-14: missing - rows 0 / floor 10 (rows when opened: 0); re-pull failed twice (command: open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily"); last try: {"at":1794768450,"method":"command","label":"command: open -g -a \"Google Chrome\" \"https://throughlinepro.com/#tl-ext-run-daily\"","rc":0}

## Cause
The BrokerBay capture has failed on every run since the 11-10 morning run, so obs dates 2026-11-09 through 11-14 all have 0 rows (11-01..11-08 have 21). The cause is a live failure in the BB step, not a missing date path. ShowingTime runs, then BB starts, and BB writes nothing. Proof: the 11-12 live smoke shows the URL-trigger run going "Daily pull complete: 8 ok" -> "BB start", yet obs 11-11 has 0 rows. The login-agent log shows ST present and the session ok on 11-13, 11-14 and 11-15. Today the supervisor fired #tl-ext-run-daily twice (13:01 and 13:47, rc=0) and 2026-11-14 still has 0 rows. No extension code changed between the last good run (11-09, v1.0.8, commit 109318f5 of 10-27) and the first bad one (11-10). The st-login-hardening change (#412) merged 11-12, after the gap started, and per its plan it does not touch BB. A code regression is therefore unlikely. The most likely runtime cause is an expired BrokerBay SSO session. In that case pullTableauDaily -> waitForEdgeSettled returns reason "auth" (bb-core.js:556-579). runBbJobInner then sets bb:status "bb_login" and returns needsLogin (bb-core.js:909-911). maybeRunBbAfterSt throws that result away (background.js:229). The bb_error paths (bb-core.js:885-888, 913-914) do the same. No ntfy goes out and nothing reaches the server, so the failure was silent for six days. I can't read the extension's chrome.storage bb:status to confirm whether it says bb_login or bb_error. A #tl-ext-repull=bb hook would call the same pullTableauDaily, so it would fail the same way until the BB session is restored. Restoring it is a human login, which is a protected action, so this needs Jim.

## Evidence
- fresh counts (is_total=eq.true): 2026-11-01..2026-11-08 = 21 each (ok); 2026-11-09, 11-10, 11-11, 11-12, 11-13, 11-14 = 0 (missing); last_complete 2026-11-08
- repull_log: [2026-11-15 13:01:34] fired open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily" for 2026-11-14 (rows before 0); [2026-11-15 13:47:31] same, rows before 0; rows_now 0 at counted_at 1794771205 -> the BB step fails live today, not just lacks a date path
- handoff/phase-5-report-st-login-hardening.md:21-22: 2026-11-12 09:10:31 URL trigger -> 09:12:15 'Daily pull complete: 8 ok, 0 failed' -> BB start; yet obs 2026-11-11 BB count = 0
- /tmp/st-login-agent.log:8-10: 2026-11-13/14/15 07:05 decision=SILENT_PRESENT, ext_last_outcome_today=login_ok/login_ok/ok -> ST lands daily; only BB is dark
- git log -- tools/showings-daily-pull: 109318f5 (2026-10-27, v1.0.8) then 269dc378 (2026-11-12, #412); no extension change around 11-09/11-10 when the gap began
- tools/showings-daily-pull/bb-core.js:556-579 waitForEdgeSettled -> reason 'auth' -> BB_SESSION_EXPIRED_MSG; bb-core.js:909-911 returns {needsLogin:true} with bb_login status only
- tools/showings-daily-pull/background.js:229 `await runBbJob({})` result discarded: no ntfy and no server record for needsLogin or bb_error (bb-core.js:885-888, 913-914), so the failure was silent for 6 days
- tools/showings-daily-pull/background.js:89-99 #tl-ext-run-daily always pulls only yesterday (pullTableauDaily default, bb-core.js:612); START_BB (background.js:771-773) takes msg.date but has no URL trigger, so the date-range hook is still needed once BB can pull again

## Decision
ESCALATED (protected action): On the Mini's Chrome, is edge.brokerbay.com signed in? (BB has written no rows since 11-10. If it's logged out, sign in once and I'll queue the date-range repull hook to backfill 11-09 to 11-14.)
- confidence: medium; protected_hit: true; needs_live_action: true

## Fresh read-only counts (2026-11-15 14:33 EST)
```json
[
  {
    "period": "2026-11-15",
    "key": "2026-11-15",
    "status": "not_ready",
    "count": null
  },
  {
    "period": "2026-11-14",
    "key": "2026-11-14",
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-13",
    "key": "2026-11-13",
    "status": "missing",
    "count": 0
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
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-10",
    "key": "2026-11-10",
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-09",
    "key": "2026-11-09",
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-08",
    "key": "2026-11-08",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-07",
    "key": "2026-11-07",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-06",
    "key": "2026-11-06",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-05",
    "key": "2026-11-05",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-04",
    "key": "2026-11-04",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-03",
    "key": "2026-11-03",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-02",
    "key": "2026-11-02",
    "status": "ok",
    "count": 21
  },
  {
    "period": "2026-11-01",
    "key": "2026-11-01",
    "status": "ok",
    "count": 21
  }
]
```

## Re-pull log (supervisor)
```
[2026-11-15 13:01:33] bb-showings-daily: command open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily"
[2026-11-15 13:01:34] bb-showings-daily: fired command: open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily" for 2026-11-14..2026-11-14 (rows before: 2026-11-14=0)
[2026-11-15 13:47:30] bb-showings-daily: command open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily"
[2026-11-15 13:47:31] bb-showings-daily: fired command: open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily" for 2026-11-14..2026-11-14 (rows before: 2026-11-14=0)
```

Full evidence: /Users/jimross/.walkaway-cli/data-fixes/bb-showings-daily-2026-11-15/handoff/evidence-bb-showings-daily-2026-11-15.json

# Data incident - bb-showings-daily - 2026-11-15

Written by the walkaway data operator (read-only) at 2026-11-15 12:36 ET.

## Gaps
- 2026-11-09: missing - rows 0 / floor 10 (rows when opened: 0); no re-pull path for age 6; last try: none
- 2026-11-10: missing - rows 0 / floor 10 (rows when opened: 0); no re-pull path for age 5; last try: none
- 2026-11-11: missing - rows 0 / floor 10 (rows when opened: 0); no re-pull path for age 4; last try: none
- 2026-11-12: missing - rows 0 / floor 10 (rows when opened: 0); no re-pull path for age 3; last try: none
- 2026-11-13: missing - rows 0 / floor 10 (rows when opened: 0); no re-pull path for age 2; last try: none

## Cause
The BB code has not changed since the data stopped. The last commits to bb-core.js and manifest BB logic are 109318f5 (10-27) and 269dc378 (11-12), and 269dc378 only touched ST login and session reporting. BB days 11-01..11-08 landed 21/21 rows on that same code. The ST→BB sequence still fires every morning. /tmp/st-login-agent.log shows ST present every day 11-11..11-14, and phase-5-report-st-login-hardening.md:22 shows a URL-triggered run on 11-12 09:12 that reached "BB start". Even so, obs_date 11-09..11-13 have 0 rows. So runBbJob starts but writes nothing, and its failure is swallowed. In bb-core.js:908-915, a dead BB session sets bb:status 'bb_login' and returns {needsLogin:true}. maybeRunBbAfterSt (background.js:228-233) drops that return value, so no ntfy or retry ever happens. Zero rows or a Tableau error (bb-core.js:880-888, 913-914) only writes a bb_error status to chrome.storage. The actual BB status text exists only in the extension's storage on the Mini, which I can't read. The most likely cause is that the BrokerBay session logged out around 11-09/11-10, which looksLikeBbDeadSession then swallows. A Tableau viz change is also possible. A BB logout needs a human login, which is protected. Building the #tl-ext-repull=bb hook now would just re-run pullTableauDaily into the same failure, and the supervisor's post-merge verification would fail too. The hook is still the right fix once the session is confirmed alive. The silent needsLogin swallow should also get a phone ping in that same plan.

## Evidence
- check: obs_date 2026-11-08..11-01 count=21 each (ok); 2026-11-09, 11-10, 11-11, 11-12, 11-13 count=0 (missing); repull_log=[]
- /tmp/st-login-agent.log: 2026-11-13 07:05:04 decision=SILENT_PRESENT yesterday=2026-11-12 present=1 ext_last_outcome_today=login_ok; 2026-11-14 07:05:05 ... yesterday=2026-11-13 present=1; 2026-11-15 07:05:02 ... yesterday=2026-11-14 present=1 (ST pull runs daily, so the BB trigger fires daily)
- handoff/phase-5-report-st-login-hardening.md:20-23: URL trigger 11-12 09:10:31 -> 'Daily pull complete: 8 ok' 09:12:15 -> BB start; yet BB obs_date 2026-11-11 has 0 rows
- git log -- tools/showings-daily-pull/bb-core.js: last BB logic change 109318f5 2026-10-27; 269dc378 (11-12) touched ST login/session reporting only (background.js, pull-core.js, offscreen.js, popup)
- tools/showings-daily-pull/bb-core.js:908-911: dead BB session -> setBbStatus bb_login + return {needsLogin:true}, no notify
- tools/showings-daily-pull/background.js:228-233: maybeRunBbAfterSt awaits runBbJob({}) and ignores needsLogin/errors (console.warn only)
- tools/showings-daily-pull/bb-core.js:880-888,913-914: zero rows / Tableau throw -> bb_error status in chrome.storage only
- tools/showings-daily-pull/background.js:771-773: START_BB(date) exists only as a runtime message; no URL trigger takes a date (background.js:89-99 handles only #tl-ext-run-daily = yesterday), hence 'no re-pull path for age 2..6'

## Decision
ESCALATED (protected action): On the Mini, what does the extension popup's BrokerBay status say? If it says BB login needs attention, is BrokerBay logged out in Chrome and can you sign it back in?
- confidence: medium; protected_hit: true; needs_live_action: true

## Fresh read-only counts (2026-11-15 12:35 EST)
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
    "status": "not_ready",
    "count": null
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

```

Full evidence: /Users/jimross/.walkaway-cli/data-fixes/bb-showings-daily-2026-11-15/handoff/evidence-bb-showings-daily-2026-11-15.json

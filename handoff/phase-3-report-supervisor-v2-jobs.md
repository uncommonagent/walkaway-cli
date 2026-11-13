# Phase 3 report - supervisor-v2-jobs (job day states, ntfy, heartbeat, tick, JOBS table; plan items 3 + 5)

- **States** (`lib/jobs.sh` jobs_evaluate / jobs_transition). There is one state file per job at `$WALKAWAY_HOME/jobs/state/<job>.json`.

  | State | Meaning | ntfy |
  |---|---|---|
  | PENDING | before the window, not run yet, or in progress | silent |
  | RETRYING | failed inside its own retry window | silent |
  | OK | done for the day | only when it resolves FAILED/FIXING/ESCALATED or a carried-over failure |
  | FAILED | daily: not OK after retry_end, or a terminal verdict (HALTED, STOP:). Rolling: RETRYING > retry_window_mins, or no success in 26 h | one line, then the job operator is spawned |
  | FIXING | a fix build is in flight | one line |
  | ESCALATED | one question for Jim | one line, priority high |

- **Rules:**
  - FAILED/FIXING/ESCALATED are sticky within a day; only OK clears them.
  - A new day resets daily jobs to PENDING. An unresolved day is carried as `unresolved_from`, and the eventual OK says "resolved (failed <date>)".
  - A source error never reads as FAILED. `WALKAWAY_JOB_ERROR_TICKS` (15) errors in a row ESCALATE once ("check broken").
  - Daily jobs already OK are not re-checked. No queries run before the window opens.
- **Supervisor:**
  - `supervisor_tick` runs `jobs.sh tick` while `$WALKAWAY_HOME/jobs.enabled` exists (still absent: job watching stays OFF until Phase 6).
  - `supervisor_heartbeat` (09/13/17) appends `jobs.sh heartbeat` lines (every non-OK job whose window has opened). A non-OK job alone justifies the heartbeat.
- **`walkaway status`** now prints the JOBS table after the build table: JOB, TODAY (state / disabled / off today), LAST OK, LAST ACTION, plus the watching on/OFF line.
- **Operator seam:**
  - On FAILED, `job-operator.sh diagnose <job> <date>` is spawned detached; on FIXING, `job-operator.sh progress <job> <date>` runs each tick.
  - The script lands in Phase 4 and is a no-op until then. `WALKAWAY_JOB_OPERATOR` overrides it for tests.
- **`tests/test-jobs-states.sh`**: 34/34 on the real jobs.yaml predicates and real rows captured read-only (tests/fixtures/jobs/), with time travel.
  - BF 11/13: RETRYING silent at 07:45, FAILED once at 12:01, resolved once; FAILED is sticky.
  - CC AM 11/04 HALTED: FAILED at once, resolved next day.
  - Extension 11/13: tracking_offsite error recovered by 08:20 with 0 ntfy; persisting 121 m → FAILED once; stale 26 h → FAILED.
  - Check errors: ESCALATED once, never FAILED.
  - RealTea: off-day; blocked → FAILED 09:16.
  - Heartbeat filter, status table.
- **Live scratch tick** (scratch home, real rows): bf-daily, cc-optin-am, spc (11/13 ACCEPTED 162/162 landed during the build), extension-reports and showingtime all OK, with 0 ntfy; realtea off today.
- **Gates:** shellcheck -S warning 0; parse 7/7, states 18/18, regression 12/12, jobs-states 34/34, operator 68/68.
- **Files:**
  - lib/jobs.sh, lib/supervisor.sh, walkaway.sh
  - tests/test-jobs-states.sh (new)
  - tests/fixtures/jobs/ (bf-1113-failures.json, bf-1113-recovered.json, cc-am-1104-halted.json, ext-state-1113.json)

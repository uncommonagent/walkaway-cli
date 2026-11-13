# Phase 1 report - supervisor-v2-jobs (DIED/DONE fix, plan item 1, AC1)

- **DONE is classified first** (`lib/supervisor.sh` supervisor_classify). The rule:
  - Applies when the build report is committed at the branch head: the file is in the branch tip, via `supervisor_report_commit` (git cat-file + git log %ct). The report's commit must be at or after the report baseline.
  - PR open: green checks → DONE (gate); pending → DONE (waits); failed → STOPPED.
  - No PR, and the plan says "no PR yet" → DONE.
  - No PR and the builder exited → STOPPED (triage).
- **DIED** now requires all three: PID gone, no build report at the branch head, and quiet for more than `WALKAWAY_DIED_GRACE_SECS` (default 180 s). Inside the grace it reads RUNNING ("exited Ns after last activity").
- **Report baseline:**
  - `registry_register` clears `.report_baseline` on every launch.
  - `op_resume` sets it back to the pre-resume baseline, so an auto-resume never invalidates a committed report.
  - Approvals and rejections still reset it: the old report no longer counts after a rejection.
- **No-op resume:** the auto-resume directive tells a resumed builder that finds everything done to:
  1. append `build-report <f> (no-op resume n/2, <ET>)` to the build report;
  2. commit and push;
  3. exit.

  The report commit then sits at the head.
- **DONE handling:** `_handle_done` starts the gate only on green checks. DONE is processed every tick, so pending → green starts the gate on the same launch. The per-launch gate guard is kept.
- STOPPED triage text covers the "report at head, no PR" case (`lib/operator.sh` op_triage).
- **AC1: `tests/test-died-done-regression.sh`** replays 11/13 through real ticks. Result: DONE at the 09:28:47-equivalent tick, 0 resumes, 0 DIED, 1 DONE ntfy; the gate starts on green.
  - 12/12 on this code.
  - 1/12 on the pre-fix lib (830b728 reproduces DIED → resume → ESCALATED).
  - Archived: handoff/supervisor-v2-jobs-evidence/ac1-regression-replay.txt.
- **State fixtures are now git-backed** (`COMMIT`, `LAUNCHED`, `BASELINE`); 18/18 pass.
  - `report-ci-pending-died` encoded the bug; it was renamed to `report-ci-pending-done` and now expects DONE.
  - New fixtures: died-within-grace-running, uncommitted-report-died, report-no-pr-stopped, report-no-pr-plan-done, resumed-report-done.
  - died and recycled-pid-died are now 5 min quiet (past the grace).
- test-operator: `WALKAWAY_DIED_GRACE_SECS=0` (kill-then-tick cases) and 2 new checks (resume baseline, no-op directive): 68/68.
- **Gates:** shellcheck -S warning 0; parse 7/7, states 18/18, regression 12/12, operator 68/68. Written and tested in /tmp/wa-dev first. After landing, the live classify gives supervisor-v2-jobs and bf-taste-scoring RUNNING.
- **Files:**
  - lib/supervisor.sh, lib/registry.sh, lib/operator.sh
  - tests/test-supervisor-states.sh, tests/test-operator.sh, tests/test-died-done-regression.sh (new)
  - tests/fixtures/states/* (6 new, 1 renamed, 6 edited)
  - handoff evidence + reports

# Evidence MANIFEST - supervisor-v2-jobs

Each acceptance criterion in handoff/build-plan-supervisor-v2-jobs.md is listed with the files that prove it. Paths are
relative to handoff/supervisor-v2-jobs-evidence/ unless noted otherwise.

## AC1: the 11/13 bf-deals-ingest-fix replay classifies DONE with zero resumes
- `ac1-regression-replay.txt`: output of `tests/test-died-done-regression.sh`.
  - On the fixed lib: 12/12. The 09:28:47-equivalent tick is DONE ("PR #28 checks pending; merge gate waits for green CI"), resume_count 0, launch_count 1, 0 DIED ntfy. The merge gate starts on green.
  - On the pre-fix lib (830b728): 1/12. It reproduces DIED → auto-resume → ESCALATED, so the test fails pre-fix.
- Code: lib/supervisor.sh supervisor_classify (DONE first, DIED grace), supervisor_report_commit and _handle_done; lib/registry.sh report_baseline; lib/operator.sh op_resume (baseline + no-op resume directive).
- Fixtures: tests/fixtures/states/{report-ci-pending-done, resumed-report-done, died-within-grace-running, uncommitted-report-died, report-no-pr-stopped, report-no-pr-plan-done}. States 18/18 (`ac5-gates.txt`).

## AC2: jobs.yaml with each job's check proven against real rows (one passing check per job, dumped)
- `../../jobs.yaml`: 8 jobs, with owner repo, window, retry_end / retry_window, check (REST + predicate), owner repo for fixes, quality_rules, protected flag, retry and diagnose.
- `phase0-job-discovery.md`: how each job was discovered and confirmed (code refs plus real rows). It also justifies each deviation from the plan's times with a real row:
  - cc-optin-am by 15:45 (11/05 DONE at 13:26 ET)
  - cc-optin-pm disabled (PM off since 10/31)
  - showingtime FAILED after 12:45
  - realtea-generate by 09:15 (11/09 08:31)
  - realtea-publish by 10:15
- `ac2-jobs-check-dump.md`: final live dump. All 8 jobs OK, each with its real query, row count, sample rows and log line. 0 key matches.
- `ac2-jobs-check-dump-phase2.md`: the first live dump (Phase 2), also 8/8 OK.
- Source of truth (spot check): Supabase tables bf_runs, cc_optin_runs, cc_spc_optins, extension_report_state, pulse_showings_daily, st_session_attempts, pulse_newsletter_issues and monday_run_reports, plus /tmp/st-login-agent.log. Every sample row in the dump is a verbatim REST response.

## AC3: drill on fixtures, exactly one ntfy per transition (drill topic)
Drill directory: `ac3-drill/`, produced by `tests/drill/run-jobs-drill.sh` using real `claude -p` and real ntfy. Result: 26/26.
Phase 6 ran on topic jim-walkaway-jobs-drill-addf5fe6. Phase 7 re-ran it on the Codex-fixed code (topic jim-walkaway-jobs-drill-fbe389ee, 12:51 ET): 26/26, 9 polled == 9 sent; `ac3-drill/` now holds that run.

| Requirement | Evidence |
|---|---|
| RETRYING, no alert | `drill-transcript.txt` (bf-daily, drill-export, extension RETRYING; "RETRYING/PENDING sent no ntfy"; extension recovered on its own retry with no ntfy). `ntfy-poll-messages.tsv` has no RETRYING line and no extension-reports line |
| FAILED → incident file + fix plan queued | `job-incident-drill-export-2026-11-13.md` (cause, evidence, decision). `build-plan-fix-drill-export-20261113.md` (template v2, `## Repo` = scratch owner repo). `nightly-export-drill.txt` (queue file holding the plan path). `state/drill-export.json` |
| FAILED with protected cause → ESCALATED with one question | `job-incident-showingtime-2026-11-13.md` (OTP/2FA, protected_hit true). The ntfy line is priority 4 (high), one line. `job-incident-bf-daily-2026-11-13.md` is the same outcome on real 11/13 rows: the fix needs live Amazon writes |
| Resolution → one ntfy | `ntfy-poll-messages.tsv`: "job drill-export: OK - resolved: total 49.75" and "job bf-daily: OK - resolved: ..." appear once each. `retry.log` has one line (the post-merge retry ran exactly once) |
| Exactly one ntfy per transition | `ntfy-poll.json` / `ntfy-poll-messages.tsv` (9 polled) == `ntfy-local.log` (9 sent). Polled transitions: drill-export [FAILED FIXING OK], bf-daily [FAILED ESCALATED OK], showingtime [FAILED ESCALATED], with no back-to-back repeat |

Supporting files: `supervisor-job-transitions.log`, `job-operator.log`, `walkaway-status-drill.txt`.

Unit level, fixture-based with no network or model: tests/test-jobs-states.sh 36/36 and tests/test-job-operator.sh 26/26 (`ac5-gates.txt`); 37/37 after the Phase 7 fixes (`ac5-gates-final.txt`).

## AC4: live supervisor on the Mini with job watching on; `walkaway status` JOBS table with today's real states
- `ac4-live/walkaway-status-live.txt` (12:16 ET): the launchd agent is active (interval 120 s, last exit 0), `jobs.enabled` exists, and the JOBS table shows bf-daily, cc-optin-am, spc, extension-reports and showingtime as OK. cc-optin-pm reads "disabled" and realtea-* read "off today".
- `ac4-live/walkaway-status-live-final.txt`: the same table, refreshed after Phase 6.
- `ac4-live/supervisor-log-job-lines.txt`: the live launchd tick at 12:14:13-14, with PENDING → OK per job on real rows.
- `ac4-live/*.json`: live job state files. `ac4-live/ntfy-since-jobs-on.log` is empty: 0 job ntfy, because nothing failed and success is silent.

## AC5: shellcheck 0, existing supervisor tests green
- `ac5-gates.txt`: `shellcheck -S warning` on every script returns rc=0. Test results:

  | Suite | Result |
  |---|---|
  | parse | 7/7 |
  | states | 18/18 |
  | AC1 | 12/12 |
  | jobs-states | 36/36 |
  | job-operator | 26/26 |
  | operator | 68/68 |

  Total: 167 checks, all passing.
- Phase 7 (after the Codex cycle 1 fixes) re-run: `ac5-gates-final.txt`. shellcheck rc=0; parse 7/7, states 18/18, AC1 12/12, jobs-states 36/36, job-operator 37/37, operator 68/68 = 178 checks, all passing; drill 26/26.

## Codex cycle 1 fixes (Phase 7): each regression fails on 4d5c8e2, passes after
Regression scenarios J7-J9 in tests/test-job-operator.sh (11 checks).
- `codex1-regression-fail-on-4d5c8e2.txt`: the new tests/test-job-operator.sh run against a scratch worktree of 4d5c8e2. Result 29/37: all 8 failures are J7-J9.
  - J7 (P1): both fix builds registered into one repo (`registered: fix-bf-daily-20261113.json fix-spc-20261113.json`).
  - J8 (P2, rollover): the retry never ran after the day-2 merge.
  - J9 (P2, queued fix): a second plan was written and `.fix_feature` was overwritten.
- `codex1-regression-pass-after-fix.txt`: the same tests on the fix, 37/37. J7: one build registered, the other plan alone in the queue, both jobs FIXING (launched / queued behind), the lock released.

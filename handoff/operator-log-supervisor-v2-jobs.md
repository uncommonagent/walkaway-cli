# Operator log - supervisor-v2-jobs

Every supervisor/operator decision for this build, newest last.

## 2026-11-13 12:32 ET - TRIAGE: APPROVE (1/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-supervisor-v2-jobs-codex.md
Rationale: This is Codex cycle 1 of 2. It found 1 P1 and 2 P2s, and all three are concrete bugs in this build's own diff (lib/job-operator.sh, lib/jobs.sh, lib/operator.sh). The fixes carry out plan item 4 as written: one builder per repo, one auto-fix per job per day, and a retry after a fix merges. They add no new feature, change none of the jobs themselves, and touch no PROTECTED action: all diagnosis stays read-only, and the drill uses only the drill ntfy topic and scratch clones. Each fix includes a regression test that must fail on 4d5c8e2 and pass after the fix, and no gate is weakened. Live exposure while the build is stopped is negligible, because no two same-repo jobs can fail together today, so job watching can stay on.
Directive written to the plan:
RESUME DIRECTIVE (operator, 2026-11-13) - supervisor-v2-jobs, Phase 7 Codex cycle 1

What failed: Codex cycle 1 at 4d5c8e2 found 1 P1 and 2 P2. The P1 is that concurrent job operators can both launch into one free repo and their queue rewrites can interleave. The P2s are that fix tracking is lost at the daily rollover, and that a queued fix with no registry entry is not seen as in flight. Details are in handoff/codex-review-supervisor-v2-jobs.md and handoff/failure-report-supervisor-v2-jobs-codex.md.

APPROVED: apply fixes 1-3 exactly as written in failure-report-supervisor-v2-jobs-codex.md.

1. P1, per-repo launch lock.
   - Add `queue_lock <repo-key>` / `queue_unlock <repo-key>` to lib/registry.sh. Use an mkdir lock at $WALKAWAY_HOME/state/queue-<repo-key>.lock. It records its pid, waits up to 120 s, and takes over a stale lock whose pid is dead.
   - `_queue_or_launch` in lib/job-operator.sh holds the lock across six steps: append to the queue, `_other_active_build`, dequeue, `_sync_default`, the walkaway launch, and the wait for registration (or the 60 s timeout).
   - `_launch_next` in lib/operator.sh takes the same lock around its queue read/rewrite and launch.
   - Release the lock on every exit path, including errors and the timeout (use a trap).
   - Regression test in tests/test-job-operator.sh: two concurrent diagnoses for two jobs in the same free scratch repo, both stub-claude decisions "fix", with a 2 s delay. Expected: exactly one fix build registered, the other plan still in the queue file, and no lost or duplicated queue lines.
2. P2, rollover. In lib/jobs.sh, `jobs_evaluate` calls `_jobs_fix_progress` whenever `.fix_feature` is set and `.retry_ran != true`, whatever the day's state. `_jobs_rollover` keeps the fix fields and sets last_action to "fix <f> still in flight". Regression test: the job is FIXING on day 1, rolls over to day 2, and the fix becomes MERGED on day 2. Expected: the retry runs exactly once, then "resolved (failed <day1>)".
3. P2, queued fix counts as in flight. In jo_diagnose, treat the previous fix as in flight in either case: its registry entry exists and is not MERGED, or no entry exists yet and its .fix_plan is still listed in the owner repo's queue file. In that case set FIXING "failed again; earlier fix <f> still queued/<state>": no new plan, `.fix_feature` unchanged, queue unchanged. Regression test: day-1 fix queued behind a busy build, the job FAILS on day 2. Expected: no second plan, nothing changed.

Each new regression test must FAIL on 4d5c8e2. Prove it: run the tests against a 4d5c8e2 checkout in a scratch worktree and archive the fail output plus the pass output after the fix to handoff/supervisor-v2-jobs-evidence/. Add both files to MANIFEST.md.

Re-run:
- `shellcheck -S warning` on all scripts (must be 0).
- Every tests/test-*.sh (all green; record the new counts).
- tests/drill/run-jobs-drill.sh (must stay 26/26, drill ntfy topic only).
- Refresh ac5-gates-final.txt.

Do not weaken or skip any existing test, gate, or acceptance criterion. Make no changes to the jobs themselves. Make no writes to job data tables.

Commit "Phase 7 fix: Codex cycle 1 P1/P2s". Run Codex cycle 2, the final one, and append it to handoff/codex-review-supervisor-v2-jobs.md. A P1 in cycle 2 stops again with a failure report. Then Phase 8: open the PR, wait for CI green, and write the build report LAST.

Then continue the plan from the build log; do not redo committed phases.

## 2026-11-13 13:29 ET - MERGE GATE: PASS (PR #2)
Verdict: PASS (screenshots opened: 0, JSON parsed: 22, rows spot-checked: 16, CI green: true, Codex closed: true)
Criteria:
- AC1: MET - ac1-regression-replay.txt: fixed lib 12/12. The 09:28:47 tick reads 'DONE - PR #28 checks pending', with resume_count 0, launch_count 1 and 0 DIED ntfy. The pre-fix lib (830b728) gets 1/12 and reproduces DIED -> auto-resume -> ESCALATED. Re-confirmed as 12/12 rc=0 in ac5-gates-final.txt (13:19).
- AC2: MET - jobs.yaml has 8 jobs with every field the plan lists. ac2-jobs-check-dump.md shows 8/8 OK, each with its verbatim REST query and sample rows: bf_runs 6 rows (ok 14:21:05Z, deals 15000), cc-optin-am DONE 16:25:19Z (export_rows 12384), spc ACCEPTED 162/162, extension_report_state 13 rows, showingtime 2026-11-12 = 2390 with decision SILENT_PRESENT, realtea #71 generated 13:31:35Z and published at the substack URL. cc-optin-pm is disabled (PM off since 10/31) and was proven on the 10/31 DONE row. Timing deviations are each justified by a real row in phase0-job-discovery.md.
- AC3: MET - ac3-drill/ (final run 13:25 on the cycle-2 code, topic jim-walkaway-jobs-drill-38ee6b0f): 26/26. ntfy-poll.json parses to 9 messages, all on the drill topic, and they match ntfy-local.log line for line (9). RETRYING ticks at 07:45 and 08:20 sent no ntfy. drill-export FAILED -> job-incident-drill-export-2026-11-13.md (cause + file:line evidence) -> template-v2 plan queued (nightly-export-drill.txt holds the plan path; plan has all v2 sections). showingtime OTP -> ESCALATED at priority 4 with one question, no plan. bf-daily on real rows -> ESCALATED (protected live action). retry.log has exactly one line. Each resolution sent one 'OK - resolved' ntfy. Transition sequences: drill-export [FAILED FIXING OK], bf-daily [FAILED ESCALATED OK], showingtime [FAILED ESCALATED], with no repeats.
- AC4: MET - ac4-live/walkaway-status-live.txt (12:16): launchd com.jimross.walkaway-supervisor is active (120 s interval, last exit 0) and ~/.walkaway-cli/jobs.enabled exists. The JOBS table shows bf-daily/cc-optin-am/spc/extension-reports/showingtime as OK, cc-optin-pm as disabled, and realtea-* as 'off today'. walkaway-status-phase8.txt shows the 13:25:30 tick on the final code. supervisor-log-job-lines.txt has the live PENDING->OK transitions at 12:14:13-14. The 7 ac4-live state JSONs agree with the table.
- AC5: MET - ac5-gates-final.txt: shellcheck -S warning rc=0. Suites: parse 7/7, states 18/18, AC1 12/12, jobs-states 38/38, job-operator 37/37, operator 68/68 = 180/180. The PR diff of tests/test-operator.sh only adds env isolation (HEARTBEAT_HOURS=off, DIED_GRACE_SECS=0, with the grace covered by its own state fixture) and 2 new checks. No existing assertion was removed or weakened.
Findings:
- Info, not blocking: the repo has no CI. There are 0 workflows, and the statusCheckRollup is empty ([]). PR #2 is OPEN, CLEAN and MERGEABLE, and its head 9077cf3 matches the local HEAD. I counted ci_green=true under the empty-rollup grace rule, the same as the PR #1 gate.
- Info, not blocking: Codex is closed. Cycle 1 (4d5c8e2) found 1 P1 + 2 P2; all were fixed, and the regressions fail before the fix (29/37) and pass after (37/37). Cycle 2 (fd20bd9) is the final one, with 0 P1. Its rollover-pid P2 was fixed (S6c 37/38 -> 38/38). Its stale-lock takeover race P2 is deferred to ROADMAP.md: it is narrow and needs a SIGKILLed lock holder plus two waiters.
- Spot check: 16 rows. 6 bf_runs rows (fixture == dump; 11:30:35Z/12:06:37Z/12:43:36Z = the plan's 06:30/07:06/07:43 ET failures), cc_optin_runs 11/13 DONE and 11/04 HALTED, cc_spc_optins 162/162, extension_report_state tracking_offsite 13:20:06Z and tracking_onsite 13:36:06Z (= the plan's 08:20/08:36 recoveries), bounty and cc rows, pulse_showings_daily 2390, and realtea #71. The ShowingTime agent line in the dump matches /tmp/st-login-agent.log line 8 verbatim. Verification limit: I did not re-query live Supabase myself, because that needs the service-role key. Supabase rows were traced to the archived verbatim REST responses, the fixtures and the plan's evidence timeline.
- Info, not blocking: tests/test-died-done-regression.sh is not heartbeat-isolated. At 13:19 it printed a duplicate RUNNING ntfy line, but it still passed 12/12. Setting WALKAWAY_HEARTBEAT_HOURS=off there, as was done in test-operator.sh, would be a good follow-up.
- Info, not blocking: there are 0 screenshots, because this build has no UI. The MANIFEST AC5 table still shows the earlier 167 count, but the same section records the final 180/180.
- Info, not blocking: the live supervisor runs lib/ from this working tree, so merging switches job watching to main's copy of the same code.

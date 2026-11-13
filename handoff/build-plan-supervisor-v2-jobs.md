# Walkaway Build Plan: supervisor-v2-jobs

## RESUME DIRECTIVE (auto, approved fix 1, 2026-11-13 12:32 ET) - read first
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

## Feature name
`supervisor-v2-jobs`

## Branch name
`feature/supervisor-v2-jobs`

## Goal
(1) No more false escalations: a builder that exits after finishing must read as DONE, never DIED.
(2) The supervisor also watches the scheduled daily jobs (extension pulls, CC opt-in, BF daily, ShowingTime, Monday
newsletter), notices a failure once its own retry window has passed, diagnoses it, and either launches a fix build
from the v2 template or escalates one question. Jim never has to notice a failed morning job.

## Evidence (do not re-derive)
- Operator log handoff/operator-log-bf-deals-ingest-fix.md (audrey-ops-platform): builder committed its build report
  at 09:28:06 and exited; DIED fired at 09:28:47; two auto-resumes found everything done; cap hit -> ESCALATED
  09:32 "Relaunch it, or stop this build?" for a finished build (PR #28 green). Classification checks DIED before
  DONE and treats a report older than the latest launch as "no new report".
- 11/13 morning: BF daily failed 3x (06:30/07:06/07:43, Deals Hub capture) and only the extension's own ntfy line
  showed it; tracking_offsite/onsite failed at 08:0x and recovered on retry 08:20/08:36.

## Decisions
- Jim 11/13: yes, add job watching with auto-fix builds.
- Protected actions unchanged (protocol + supervisor): spend, credentials, live customer-facing writes, data
  deletion, unqueued features, anything marked Jim decides.

## Quality rules
Protocol "Merge-gate acceptance standard" + template v2 (BPO handoff). Every auto-generated fix plan must follow
template v2 and cite the domain quality-rules file when the job touches Showrunner lists.

## Source of truth
Supabase tables (both projects: audrey-ops-platform .env.local and throughline-app env): extension_report_state,
cc_optin_runs, cc_spc_optins, bf_runs, bf_lists; Throughline: pulse_showings_daily, st session-state table (PR
#412), pulse_newsletter_issues + Substack publish write-back; launchd agent logs (/tmp/st-login-agent.log).

## What to build
1. DIED/DONE fix: classify DONE first when a build report for the feature exists and its commit is on the branch
   head and the PR is open (or the plan says no PR yet); a resumed builder that finds nothing to do writes
   "build-report ... (no-op resume)" and exits; DIED requires: PID gone AND no build report at branch head AND last
   activity older than 3 min (grace). Regression test from the 11/13 timeline.
2. jobs.yaml (walkaway-cli): each job = name, repo, schedule window (local), retry window end, check (REST query
   + predicate), owner repo for fixes, quality-rules file, protected flag. Phase 0 discovers and confirms each job
   from the repos and the router doc (ops/handoff/combined-thread-context-*.md) before writing it:
   BF daily (ok today by 12:00), CC opt-in AM (DONE by 12:00) / PM (DONE by 19:30), SPC (run_date today by 17:30),
   extension reports (each type success within 26 h; error persisting > 2 h), ShowingTime (yesterday row by 07:30,
   agent decision not ACT_*), Monday RealTea (issue generated by 08:30 Mon, Substack published by 10:00 Mon).
3. Job states per day: PENDING, OK, RETRYING (failed inside its own retry window - wait, no alert), FAILED (window
   passed), FIXING, ESCALATED. ntfy one line on FAILED and on resolution; the 09/13/17 heartbeat lists any
   non-OK job.
4. On FAILED: operator diagnoses read-only (rows, error messages, logs; no writes), writes
   handoff/job-incident-<job>-<date>.md (cause + evidence), then either (a) writes a template-v2 fix plan in the
   owner repo and queues/launches it (one auto-fix build per job per day; respects one builder per repo), or
   (b) ESCALATES one question when the cause or fix touches a protected action or is unclear. After a fix merges,
   it triggers the job's retry path if the job has one (e.g. BF daily run-now) and confirms OK.
5. `walkaway status` gains a JOBS table (job, today state, last OK, last action).

## Do NOT build
No changes to the jobs themselves (fixes go through separate builds). No new dashboards.

## Acceptance criteria
- [ ] AC1 Regression test replaying the 11/13 bf-deals-ingest-fix timeline classifies DONE, zero resumes.
      (evidence: test output)
- [ ] AC2 jobs.yaml with each job's check proven against real rows (one passing check per job, dumped).
- [ ] AC3 Drill on fixtures: RETRYING (no alert), FAILED -> incident file + fix plan queued, FAILED with protected
      cause -> ESCALATED with one question, resolution -> one ntfy. Exactly one ntfy per transition (drill topic).
- [ ] AC4 Live: supervisor loaded on the Mini with job watching on; `walkaway status` shows the JOBS table with
      today's real states (archived).
- [ ] AC5 shellcheck 0, existing supervisor tests green.

## Gate checklist
Run AC1 test; open the jobs check dump (each job has a real row); open drill transcript and count ntfy lines per
transition; read the live status output.

## Stop rules
Never write to job data tables or trigger a job's live action during the build except through a documented
read-only check. No real customer-facing action.

## Escalate to Jim
Any job fix that would publish, spend, touch credentials, or delete data.

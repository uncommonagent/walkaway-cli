# Walkaway Build Plan: build-supervisor

## RESUME DIRECTIVE (auto, approved fix 2, 2026-11-12 15:52 ET) - read first
RESUME DIRECTIVE (operator, approved) - build-supervisor, Phase 7 Codex cycle 2 (FINAL)

What failed: Codex cycle 2 (HEAD 3f4af2b) found 2 P1 and 1 P2 in the lib/operator.sh merge path: stale-check green, post-merge sync while a builder is active in the root checkout, and a swallowed gate push failure. Full text: handoff/codex-review-build-supervisor.md.

Apply the fixes as proposed in handoff/failure-report-build-supervisor-codex-cycle-2.md:
1. P1, stale checks (lib/supervisor.sh supervisor_pr_json + lib/operator.sh _wait_checks_green):
   - Add headRefOid to the `gh pr view --json` fields.
   - After the gate push, record sha=$(git -C <repo> rev-parse HEAD).
   - A lookup is valid only if .number is set, .state == "OPEN" and .headRefOid == sha.
   - A head mismatch means pending. Keep polling until WALKAWAY_MERGE_CHECK_WAIT runs out, then escalate with no merge. A head mismatch is not a lookup failure.
   - An empty rollup on the matching head stays pending for WALKAWAY_MERGE_EMPTY_CHECKS_GRACE (default 120 s), then counts as green.
   - The existing fail-closed lookup-failure rule stays: 3 consecutive failures -> escalate.
   - tests/drill/gh-sim.sh returns headRefOid from the pushed branch tip.
2. P1, post-merge sync under an active builder (op_post_merge / _sync_default / _launch_next):
   - Add one shared helper that finds another registered, non-MERGED build whose .repo == repo_root. Use it in both _sync_default and _launch_next.
   - If such a build exists, run only `git -C <root> fetch -q origin` and log "default-branch sync deferred: <feature> active in root". No checkout, no pull. The queue stays held.
3. P2, gate push failure (op_gate PASS branch):
   - _commit_decision returns success or failure.
   - Replace `git push ... || true` with a checked push.
   - If the commit or the push fails: op_escalate "Merge gate PASS for <f> could not be pushed (<last line>). Push/merge manually?". Do not wait for checks and do not run gh pr merge.

Regression tests in tests/test-operator.sh. Each must fail on 3f4af2b and pass after the fix. Record the fail-then-pass result in the build log.
- gh-sim reports the old head with a green rollup after the gate push -> no merge until the head matches. If the head never matches -> escalate, no merge.
- Empty rollup on the matching head -> merge only after the grace window (set the grace to 2 s in the test).
- A worktree build merges while another registered build is running in the root checkout -> the root's branch and HEAD are unchanged, no checkout or pull ran, and the queue is held.
- The gate push fails (origin made unwritable or a pre-push hook rejects it) -> escalate, gh pr merge not called.

Re-run every gate:
- `shellcheck -S warning` on all scripts: must be 0.
- tests parse 7/7, states 13/13 and operator: all green, with the new count.
- Commit with a "Phase 7 fix: Codex cycle 2 P1/P2s (approved fix 2)" message and append a build-log line.

Codex closure (no cycle 3, cap reached):
- Append "## Cycle 2 fixes (<sha>, approved fix 2)" to handoff/codex-review-build-supervisor.md. List each finding -> fix -> the regression test name with its fail-on-3f4af2b / pass-now result.
- Set "Cycle-2 status: CLOSED by regression-test evidence (cap 2, no cycle 3, per operator approval)".

Follow-ups: log the four follow-ups from the failure report's Notes to ROADMAP follow-ups (protocol: remaining items after cycle 2 go to ROADMAP). They are: the lib/watcher.sh:74 substring glob, the bpo-j naming ambiguity, the protocol line 457 report-name doc, and the ntfy relaunch-label race. Do not build them.

Then continue the plan from the build log: Phase 8, open the PR, wait for CI, write the build report LAST. Do not redo committed phases 0-6. Never merge.

## RESUME DIRECTIVE (auto, approved fix 1, 2026-11-12 15:37 ET) - read first
RESUME DIRECTIVE (operator, approved) - build-supervisor, Phase 7 Codex cycle 1

What failed: Codex cycle 1 (HEAD 4e6fabc) found 2 P1 and 3 P2 in lib/operator.sh and lib/supervisor.sh (full text: handoff/codex-review-build-supervisor.md).

Apply the fixes as proposed in handoff/failure-report-build-supervisor-codex.md:
1. P1, worktree pruned before merge (lib/operator.sh op_gate PASS branch): remove the `_prune_worktree` call that runs before `gh pr merge`.
   - Worktree builds: merge with `gh pr merge <n> --squash` (no --delete-branch). Only after the merge succeeds: prune the worktree, then `git -C <repo_root> push origin --delete <branch>`, then `git -C <repo_root> branch -D <branch>`.
   - Non-worktree builds: keep `--squash --delete-branch`.
   - If the merge fails, remove nothing. The escalation must log into the intact worktree.
2. P1, fail-open CI wait (lib/operator.sh `_wait_checks_green`): treat the PR JSON as valid only if `.number` is set and `.state == "OPEN"`.
   - Anything else counts as a lookup failure: retry. After 3 consecutive lookup failures, return 1 so the caller escalates.
   - An empty check rollup may count as green only after a valid lookup.
3. P2, Codex closure (lib/operator.sh op_gate): extend the deterministic downgrade so a PASS verdict becomes FAIL unless `codex_closed == true`. Keep the existing unmet-criterion and ci_green checks.
4. P2, failure-report matching (lib/supervisor.sh classify + lib/operator.sh `_newest_failure_report`): factor one shared helper used by both.
   - Match only `failure-report-<feature>.md` and `failure-report-<feature>-<suffix>.md` where <suffix> starts with phase, codex or context.
   - Add the fixture tests/fixtures/states/other-feature-report-running: report `failure-report-demo-next-phase-3.md`, newer than launch, must classify as RUNNING.
5. P2, post-merge log (lib/operator.sh op_post_merge): stop appending the MERGED entry to the repo checkout after cleanup.
   - The "MERGE GATE: PASS" entry stays committed and pushed in the PR before the merge.
   - The MERGED outcome goes only to $WALKAWAY_HOME/logs/operator-<feature>.log, the registry and ntfy.
   - Nothing uncommitted may be written to the default branch or to the next feature's checkout.

Regression tests in tests/test-operator.sh (each must fail on 4e6fabc and pass after the fix):
- PASS verdict with codex_closed:false -> FAIL/rejection directive, gh pr merge NOT called.
- gh pr view failing during `_wait_checks_green` -> escalate, no merge.
- Worktree build where `gh pr merge` fails -> worktree still a valid git worktree (git -C <wt> rev-parse succeeds), branch not deleted, escalation logged inside it.
- Worktree build where the merge succeeds -> merge is called without --delete-branch, the worktree is pruned after the merge, and the remote and local branch are deleted.
- After a merge, `git status --porcelain` in the repo checkout is empty (no uncommitted operator-log change).
- The new states fixture is included in tests/test-states.sh.

Re-run every gate:
- `shellcheck -S warning` on all scripts: must be 0.
- tests parse, states (now 13/13) and operator: all green.
- Commit with a Phase 7 fix message and append a build-log line.

Then run Codex cycle 2 (`codex review --base main`). It is the FINAL cycle (cap 2):
- Record it in handoff/codex-review-build-supervisor.md.
- Fix any P2s in scope, with tests.
- If cycle 2 returns any P1, STOP and write a new failure report. Do not start cycle 3.

Then continue the plan from the build log: Phase 8, open the PR, wait for CI, write the build report LAST. Do not redo committed phases 0-6. Never merge.

## Feature name
`build-supervisor`

## Branch name
`feature/build-supervisor`

## Goal
Builds never sit idle and Jim never has to ask "status". A supervisor on the Mini knows the true state of every
walkaway build, pushes one ntfy line on every state change, and resolves routine stops, silent deaths, stalls, and
merge gates by itself, escalating only real decisions.

## Evidence (11/12)
- lib/watcher.sh only notifies when build-report-<f>.md or failure-report-*<f>*.md appears, then exits. A builder that
  exits without writing a report (crash, session end, context limit) produces NO ntfy, and nothing resumes it.
- Stops that do notify still wait for a human: only Claude-in-chat writes resume directives and relaunches.
- Status checks matched processes by name ("dangerously") and once misread a live builder as dead (14:10).
- Today: idea-list-review, bf-lists-daily, st-login-hardening, review-page-v4 each stopped 1-3 times; every stop
  had a fix that was later approved unchanged or with a one-line addition.

## What to build (walkaway-cli repo + one launchd agent on the Mini)
1. Registry: walkaway writes ~/.walkaway-cli/registry/<feature>.json at launch {feature, repo, plan, branch,
   builder_pid, watcher_pid, launched_at, resume_count, gate_rejections, queue_next}. PIDs come from the launch
   itself, never from name matching. Every relaunch updates it.
2. Supervisor (supervisor.sh + launchd com.jimross.walkaway-supervisor, every 2 min, single-instance lock):
   state per registered build from (a) builder PID alive, (b) newest mtime under handoff/ + branch HEAD time,
   (c) report files, (d) gh pr state + checks. States: RUNNING, STALLED (alive, no activity 40 min), STOPPED
   (failure report newer than last launch), DIED (PID gone, no new report), DONE (build report + PR open + checks
   green), MERGED, ESCALATED. ntfy (topic jim-throughline-9k2x7q-builds) on EVERY transition, one line:
   "<feature>: <state> - <action taken>". A heartbeat ntfy at 09:00/13:00/17:00 ET only if something is
   RUNNING/ESCALATED: one line per build.
3. Operator (headless `claude -p` with a fixed system prompt file operator-prompt.md that encodes Jim's operating
   standard + handoff/WALKAWAY_BUILD_PROTOCOL.md + the plan + its reports). Invoked by the supervisor on:
   - DIED/STALLED: kill leftovers, write "RESUME DIRECTIVE (auto)" = continue from the build log, do not redo
     committed phases; relaunch. Cap 2 per build, then ESCALATE.
   - STOPPED: triage the failure report. If the proposed fix stays inside the plan's scope and touches no PROTECTED
     action, write the approving directive (fix as proposed, plus any obvious additions it would make) and relaunch.
     Otherwise ESCALATE with ONE specific question to Jim (ntfy priority high), and wait.
   - DONE: merge gate. Read the plan's acceptance criteria and verify the archived evidence itself: open every
     screenshot (vision), parse audit/summary JSON, spot-check at least 10 data rows against source data, confirm
     CI green + Codex closed. PASS -> gh pr merge --squash --delete-branch (prune worktrees first), kill builder +
     watcher, update registry, launch queue_next. FAIL -> write a "merge-gate rejection" directive with exact
     findings and relaunch (cap 2 rejections, then ESCALATE).
   Every operator decision is appended to handoff/operator-log-<feature>.md and committed.
4. PROTECTED actions (always ESCALATE, never automatic): spend or plan/tier changes; credentials or secrets; writes
   or publishes to Audrey's live Amazon lists/curations or any customer-facing send outside a plan's explicit
   throwaway; data deletion beyond throwaways a plan names; launching a feature not already queued; anything a
   plan or report marks "Jim decides"; any operator uncertainty.
5. Queue: ~/.walkaway-cli/queue/<repo>.txt (ordered plan paths). On MERGED the supervisor launches the next plan
   for that repo (one builder per repo; repos in parallel).
6. Protocol update (handoff/WALKAWAY_BUILD_PROTOCOL.md in ops): Codex P1 stops route to the operator instead of
   waiting for Jim; Codex cap stays 2.
7. `walkaway status`: one table from the registry (feature, repo, state, age, last action) for Claude-in-chat
   status checks. Claude-in-chat stops using name-matched ps.

## Do NOT build
No changes to how builders run phases. No auto-merge for PRs not launched by walkaway. No dashboards.

## Acceptance criteria
- [ ] AC1 Unit tests (bats or shell tests) for state classification from fixture dirs: each of the 7 states.
- [ ] AC2 Live drill in a scratch repo (walkaway-cli/tests/drill, throwaway plan): (a) kill the builder mid-phase ->
      DIED ntfy + auto-resume within 4 min; (b) builder writes a scoped failure report -> operator approves +
      relaunch; (c) failure report with a PROTECTED action -> ESCALATE ntfy with one question, no relaunch;
      (d) build completes with a bad evidence file -> gate rejection directive; (e) good evidence -> merged + next
      queued plan launched. Every transition produced exactly one ntfy (capture via ntfy JSON poll).
- [ ] AC3 launchd agent installed and loaded on the Mini; supervisor adopts the currently running builds
      (registry backfill for live PIDs found via the walkaway launch logs).
- [ ] AC4 `walkaway status` output archived.
- [ ] AC5 Protocol doc updated in ops and committed.

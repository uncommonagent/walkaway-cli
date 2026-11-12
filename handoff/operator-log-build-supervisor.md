# Operator log - build-supervisor

Every supervisor/operator decision for this build, newest last.

## 2026-11-12 15:37 ET - TRIAGE: APPROVE (1/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-build-supervisor-codex.md
Rationale: I checked all five fixes against the plan. Each one corrects a concrete defect in operator or supervisor code that plan items 2 and 3 require, and none of them changes how builders run phases. Fix 1 still deletes the branch after the merge, which plan item 3 already requires; it just moves the worktree prune and branch delete to after a confirmed merge. The P1s are code defects, not design or scope questions, and no protected action is involved. I added the obvious missing pieces: a regression test for a failed merge in a worktree build, shellcheck/test gates, and the rule that Codex cycle 2 is the last one.
Directive written to the plan:
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

## 2026-11-12 15:52 ET - TRIAGE: APPROVE (2/3)
Report: /Users/jimross/Projects/walkaway-cli/handoff/failure-report-build-supervisor-codex-cycle-2.md
Rationale: Codex cycle 2 found two P1s and one P2, all in the merge path of lib/operator.sh (plan item 3: the merge gate and post-merge steps). The builder confirmed each one against the code. Protocol line 498 says P1s go to the operator and that there is no cycle 3, so option (a) is the protocol path: fix the findings, prove each fix with a test that fails before it and passes after, and close by that test evidence. Every fix makes the gate stricter: checks must match the pushed head, there is an empty-rollup grace window, the root checkout is not switched while a build is active there, and a failed push escalates. None of them weakens a gate or touches a protected action. This is consistent with approved fix 1.
Directive written to the plan:
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

## 2026-11-12 16:13 ET - MERGE GATE: PASS (PR #1)
Verdict: PASS (screenshots opened: 0, JSON parsed: 11, rows spot-checked: 18, CI green: true, Codex closed: true)
Criteria:
- AC1: MET - tests/fixtures/states/ has 13 fixture dirs, including running, stalled, stopped, died, done, merged and escalated. tests/test-supervisor-states.sh:83 loops over all 7 states. The build log's final gates line records states 13/13, operator 66/66 and parse 7/7. My own re-run of the tests and shellcheck was blocked by a permission prompt, so this rests on the archived build-log results.
- AC2: MET - Checked against handoff/drill-evidence-build-supervisor/. ntfy-poll.json parses to 12 messages, and they match ntfy-local.log and ntfy-poll-messages.tsv line for line. (a) Kill at 20:26:06Z, DIED ntfy at 20:28:07Z, new builder 19210 launched at 20:28:07Z (registry drill-a.json resume_count 1, launch_count 2). That is 121 s, under the 240 s limit. (b) drill-b.json approvals 1, launch_count 2, and the plan carries a RESUME DIRECTIVE. (c) The ESCALATED ntfy has priority 4 and asks one yes/no question. drill-c.json shows launch_count 1, and the plan has 0 directives, so no relaunch happened. (d) gate-drill-d.md FAILs on row 7 (99.99 vs 52.25) and total (452.00 vs 417.50), and the rejection directive is in the plan (gate_rejections 1). (e) gate-drill-e.md PASSes. drill-re-origin-main.log shows squash commit 9bd00a1, and drill-e2.json was launched from the queue (pid 17871). No feature repeats a state back to back.
- AC3: MET - In live-install-evidence-build-supervisor/: launchctl-print.txt shows com.jimross.walkaway-supervisor loaded with last exit code 0. supervisor.log has 'LAUNCHED -> RUNNING - builder pid 11000'. registry-build-supervisor.json has adopted:true, builder 11000 and watcher 11041. The real-topic ntfy poll has tXJ25yUdpEDJ RUNNING. Two live triage loops (m0v4XW0QmKvH -> wG7gBav1iEom and qYnjYxwCULHR -> R11YwSNratD3) show registry approvals 2 and launch_count 3.
- AC4: MET - walkaway-status.txt is archived three ways: live at 15:33 (build-supervisor RUNNING, pid 11000), live-triage-2 at 16:03 (pid 69927), and the drill (6 builds).
- AC5: MET - bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md has the updates. Lines 11-32 add walkaway status and the operator owning resume, triage and the merge gate. Line 98 covers the supervisor ntfy. Line 491 routes Codex P1 to the operator. Line 498 keeps the cap at 2. The builder reports it as commit 82d2446, local and unpushed. I could not confirm the SHA myself because git in that repo was blocked by a permission prompt.
Findings:
- Info, not blocking: the repo has no CI. gh pr checks 1 reports 'no checks reported'. PR #1 is OPEN, CLEAN and MERGEABLE, and its head 872e760 matches the local HEAD. I counted ci_green=true as 'no failing or pending checks', which matches the gate's empty-rollup grace rule.
- Info, not blocking: the AC5 protocol commit 82d2446 sits on bpo-comp-tool main and has not been pushed. Pushing it is Jim's decision and is outside this PR.
- Info, not blocking: the AC2 drill was not re-run after fix 2 (gh-sim merge path changed). This is disclosed, and regression tests T6/T11/T12-T15 cover the change (operator 66/66 per the build log).
- Info, not blocking: the live real-topic poll includes 3gNyWQ9vWtGQ, a priority-5 ping from watcher 11041, which predates the supervisor. It is a double-ping the builder disclosed in the phase-7 report. Watchers launched later stayed suppressed, and loop 2 shows 5 sends == 5 messages.
- Verification limit: I could not re-run tests or shellcheck myself, or run git in bpo-comp-tool, because of permission prompts. AC1 and AC5 rest on archived results and the file content I read.

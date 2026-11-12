# Failure report - build-supervisor - Phase 7 (Codex cycle 2, FINAL)

## Phase / gate
Phase 7, Codex cycle 2 (`codex review --base main` at 3f4af2b). The Codex cap of 2 cycles is now reached. Cycle 2
returned 2 P1 + 1 P2, all in lib/operator.sh's merge path (full text: handoff/codex-review-build-supervisor.md). The
approved directive (fix 1) says: "If cycle 2 returns any P1, STOP and write a new failure report. Do not start cycle 3."
So the builder stopped here: no Phase 8, no PR, no build report.

State at stop: cycle-1 fixes are committed in 3f4af2b. Gates are green: shellcheck -S warning 0; parse 7/7;
states 13/13; operator 51/51. Phases 0-6 are unchanged. Commit 79ef8f6 records cycle 2 and the live triage
evidence.

## What was attempted
Nothing for cycle 2. This is a stop rule and no fixes were attempted. I checked all three findings against the code
and they are real:
- `_wait_checks_green` never compares the PR head to the commit it just pushed.
- `_sync_default` runs in `op_post_merge` before `_launch_next` checks for an active build.
- The gate push is `git push ... || true`.

## Proposed fix (in plan scope: item 3, merge gate; files lib/operator.sh, lib/supervisor.sh, tests/test-operator.sh, tests/drill/gh-sim.sh)
1. **P1, stale checks.** Changes in `supervisor_pr_json` and `_wait_checks_green`:
   - Add `headRefOid` to the `gh pr view --json` fields.
   - After the gate push, record `sha=$(git -C <repo> rev-parse HEAD)`.
   - A lookup counts as valid only if `.number` is set, `.state == "OPEN"` and `.headRefOid == sha`. A head mismatch
     means "still pending" (keep polling until WALKAWAY_MERGE_CHECK_WAIT runs out, then escalate). It is not a lookup
     failure.
   - An empty rollup on the matching head is treated as pending for a grace window, WALKAWAY_MERGE_EMPTY_CHECKS_GRACE
     (default 120 s). After that window it counts as green. That lets repos with no CI merge: walkaway-cli itself has
     no .github/workflows.
   - gh-sim: return `headRefOid` from the pushed branch tip.
2. **P1, post-merge sync under an active builder** (`op_post_merge` / `_sync_default`). Before switching the root
   checkout, look for any other registered, non-MERGED build whose `.repo == repo_root` (a builder working in the main
   checkout).
   - If one exists: run only `git -C <root> fetch -q origin` and log "default-branch sync deferred: <feature> active
     in root". Make no checkout and no pull.
   - `_launch_next` already holds the queue in that case.
   - Hoist the shared "active build in this root" check into one helper, used by both functions.
3. **P2, gate push failure** (op_gate PASS branch).
   - `_commit_decision` reports whether the commit succeeded.
   - Replace `git push ... || true` with a checked push.
   - If the commit or the push fails: `op_escalate "Merge gate PASS for <f> could not be pushed (<last line>).
     Push/merge manually?"`. Do not wait for checks and do not merge.

Regression tests in tests/test-operator.sh. Each must fail on 3f4af2b and pass after the fix:
- gh-sim reports the old head with a green rollup after the gate push → no merge until the head matches. If it never
  matches → escalate, no merge.
- Empty rollup on the matching head → merge happens only after the grace window. Set the grace to 2 s in the test.
- A worktree build merges while another build is registered and running in the root checkout → the root's branch is
  unchanged, the root has no new checkout, and the queue is held.
- The gate push fails (gh-sim origin made unwritable, or a push hook rejects it) → escalate, `gh pr merge` not called.

Then re-run every gate. After that: open the PR, wait for "CI", and write the build report LAST.

## Decision needed (Codex cap)
Codex's 2-cycle cap is spent. Protocol options: (a) apply these fixes with regression tests and continue to Phase 8
with no cycle 3, closing the findings by test evidence; (b) authorize a one-off cycle 3 to confirm the fixes; (c) Jim
decides. The fixes are small and in scope, and each has a failing-then-passing test. I recommend (a), with the gate
operator confirming the four new tests in the evidence.

## Notes
- No PROTECTED action is involved.
- This build is supervised by the live supervisor (registry: launch_count 2, approvals 1/3). This report is its
  second real triage.
- Follow-ups outside this fix:
  - lib/watcher.sh:74 still uses the substring glob `failure-report-*<feature>*`. Watchers are suppressed while the
    supervisor is installed.
  - Inherent naming ambiguity: a feature `bpo-j` would still match `failure-report-bpo-j-phase-5-5-...-phase-0.md`,
    a real report name from another build.
  - Protocol line 457 documents `failure-report-<feature>-<phase>.md`. A builder that writes a bare-number suffix
    such as `-3` would not match. Every real report found across ~/Projects uses `-phase-N` or `-codex`.
  - Cosmetic race: the first RUNNING ntfy after a relaunch can miss the "approved fix N" label. registry_register
    nulls operator_pid before the operator records its action.

# Phase 7 report - build-supervisor (Codex review) - CLOSED (cycle 2 fixed by approved fix 2)

- Cycle 1 (4e6fabc): 2 P1 + 3 P2 -> failure-report-build-supervisor-codex.md -> the LIVE supervisor triaged it with a
  real `claude -p` operator (APPROVE 1/3, 15:37 ET) and relaunched this builder (pid 34230). This is a real-system
  run of the STOPPED -> approve -> relaunch loop on the supervisor's own build (evidence below).
- Approved fix 1 applied in 3f4af2b: all 5 findings fixed; 13 new operator checks + 1 new state fixture, each verified
  to FAIL on 4e6fabc lib/ and PASS on 3f4af2b (38/51 and 12/13 on the old code; 51/51 and 13/13 now).
- Also fixed a test race (pre-existing, flaked once in T3): `wait_operator` returned as soon as a relaunch
  re-registered (operator_pid -> null), before the operator recorded its action. Same sub-second window exists in
  production; effect is cosmetic (the first RUNNING ntfy may lack the "approved fix N" label). Flagged, not fixed.
- Cycle 2 (3f4af2b, FINAL): 2 P1 + 1 P2, all confirmed against the code. Per the directive: STOP, no cycle 3, no PR.
  failure-report-build-supervisor-codex-cycle-2.md carries the proposed fixes.
- Gates at 3f4af2b: shellcheck -S warning rc=0; parse 7/7; states 13/13; operator 51/51 (run twice, stable).
- Live evidence (handoff/live-install-evidence-build-supervisor/live-triage-2026-11-12/): real-topic ntfy poll
  m0v4XW0QmKvH 20:37:33Z "build-supervisor: STOPPED - failure-report-build-supervisor-codex.md; operator triage
  started", wG7gBav1iEom 20:39:34Z "build-supervisor: RUNNING - approved fix 1, relaunched (builder pid 34230)";
  supervisor.log transitions; registry (launch_count 2, approvals 1); operator commit 3c06829. Also 3gNyWQ9vWtGQ
  (20:36:19Z, priority 5) = the pre-supervisor watcher 11041's own ping, the double-ping predicted in the cycle-1 report.
- Files (3f4af2b): lib/operator.sh, lib/supervisor.sh, tests/test-operator.sh, tests/drill/gh-sim.sh,
  tests/fixtures/states/other-feature-report-running/{fixture.env,pr.json,handoff/*}, README.md,
  handoff/build-log-build-supervisor.md. Stop commit: handoff/codex-review-build-supervisor.md, this report,
  handoff/failure-report-build-supervisor-codex-cycle-2.md, live-triage evidence, build log.

## Approved fix 2 (operator triage of the cycle-2 report, 15:52 ET) -> 3f4538d
- The live supervisor's operator approved the cycle-2 failure report (operator commit afd472f, approval 2/3) and
  relaunched this builder. This is the second real STOPPED -> approve -> relaunch run on the supervisor's own build.
- Fixes, all in lib/operator.sh and lib/supervisor.sh:
  - CI wait is bound to the pushed gate commit (`headRefOid`), with an empty-rollup grace window.
  - The post-merge sync is deferred while another build is active in the root checkout. It uses the shared
    `_other_active_build` helper.
  - A gate commit or push failure now escalates instead of merging.
- gh-sim: reports `headRefOid` from the origin branch tip, adds `stale-head` / `empty-checks` knobs and epoch
  timestamps in calls.log, and squash-merges in a temp clone of origin. The old version did `git checkout main` in
  the root checkout, which hid the P1-2 scenario. The new one only touches a local checkout under
  `--delete-branch`, the way gh does.
- Regression tests T12, T12b, T13, T14 and T15 (16 checks; 9 FAIL on 3f4af2b lib/, all PASS now).
- Gates at 3f4538d:
  - shellcheck -S warning: rc=0, combined and per file. Checking per file exposed 2 pre-existing SC2034 (unused
    loop vars in tests/test-operator.sh) that the combined run masked; both fixed.
  - parse 7/7, states 13/13, operator 66/66.
- Not re-run: the AC2 live drill (tests/drill/run-drill.sh). It installs a second launchd agent, makes real
  `claude -p` calls and ntfy pushes, and rewrites the committed Phase 6 evidence. The only drill-relevant change is
  gh-sim's merge implementation. Both merge forms the drill uses (non-worktree `--delete-branch` + queue launch,
  and worktree) are exercised by T6 and T11, which pass.
- Codex closure: "Cycle 2 fixes" section added to handoff/codex-review-build-supervisor.md. Cycle-2 status: CLOSED
  by regression-test evidence (cap 2, no cycle 3).
- Follow-ups (not built) logged to ROADMAP.md: watcher substring glob, bpo-j prefix ambiguity, protocol
  report-name doc, relaunch-label ntfy race.
- Files: lib/operator.sh, lib/supervisor.sh, tests/drill/gh-sim.sh, tests/test-operator.sh, ROADMAP.md (new),
  handoff/codex-review-build-supervisor.md, handoff/build-plan-build-supervisor.md (fix-1 directive marked [DONE]),
  this report, handoff/build-log-build-supervisor.md.

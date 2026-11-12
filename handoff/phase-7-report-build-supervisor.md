# Phase 7 report - build-supervisor (Codex review) - STOPPED at cycle 2

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

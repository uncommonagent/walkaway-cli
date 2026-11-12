# Phase 6 report - build-supervisor (smoke: live drill, live install, status, protocol)

- AC2 PASS: live drill under a real launchd agent with real `claude -p` operator decisions and real ntfy (drill topic, JSON poll). (a) auto-resume 121 s after kill; (b) approve + relaunch; (c) PROTECTED -> ESCALATED one question, no relaunch; (d) gate rejection directive + relaunch; (e) PASS -> squash-merge + queued plan launched. 12/12 ntfy 1:1, no repeats. See smoke-results-build-supervisor.md.
- Drill attempts 1-3 found real defects, all fixed and pinned by tests before the final run:
  1. launchd kills the tick's whole process group on exit -> every relaunched builder and detached operator job died (operator "exited without decision"). Fix: `AbandonProcessGroup` in the plist.
  2. `awk -v body=` rejects newlines -> every model-written (multi-line) directive was dropped and a stray `<plan>.tmp.<pid>` left behind (which a builder then committed). Fix: head/printf/tail insert + tmp cleanup; regression check in test-operator T3.
  3. Operator actions were invisible in ntfy (relaunch went LAUNCHED -> RUNNING with only a PID). Fix: first RUNNING after an operator relaunch carries the action ("approved fix 1, relaunched ..."); test added.
  4. (harness) gh-sim PR-number race; drill "good" stub lacked the plan deliverable lib/export.sh + MANIFEST - the real operator correctly FAILED it, which is the gate working.
- Added per protocol "Merge-gate acceptance standard" rule 10 (committed today in dd25976): the operator writes `handoff/gate-<feature>.md`; prompt points at that section.
- Post-merge now always fast-forwards the repo's default branch (clean trees only), not just when a queue exists - otherwise merging walkaway-cli's own PR would leave the launchd agent running stale code.
- AC3 PASS: real agent installed + loaded on the Mini; adopted the live build-supervisor builder 11000 via watcher->PPID lineage; first tick RUNNING; real-topic ntfy confirmed by poll (id tXJ25yUdpEDJ).
- AC4 PASS: `walkaway status` archived (live + drill). AC5 PASS: protocol committed 82d2446 in bpo-comp-tool (local only, not pushed).
- Deviations: drill ntfy used a dedicated topic (not Jim's phone topic) to avoid ~12 test pings; gh is simulated in the drill (scratch repos have no GitHub remote). Live install uses the real topic + real gh.
- Gates: shellcheck -S warning rc=0; parse 7/7, states 12/12, operator 31/31.
- Files: install-supervisor.sh, lib/operator.sh, lib/supervisor.sh, templates/operator-prompt.md, tests/test-operator.sh, tests/drill/{run-drill,gh-sim,scratch,stub-builder}.sh, .gitignore, handoff/drill-evidence-build-supervisor/**, handoff/live-install-evidence-build-supervisor/**, handoff/smoke-results-build-supervisor.md; external: bpo-comp-tool handoff/WALKAWAY_BUILD_PROTOCOL.md.

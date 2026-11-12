# Smoke results - build-supervisor (Phase 6, 2026-11-12)

## AC2 live drill - `tests/drill/run-drill.sh` (final run 15:24:04-15:30:17 ET, 373 s)
Real launchd agent `com.jimross.walkaway-supervisor-drill` (StartInterval 120), real walkaway launches, real stub-builder
processes, real `claude -p` operator decisions, real ntfy pushes to drill topic `jim-walkaway-drill-8fc78861`
(captured via `https://ntfy.sh/<topic>/json?poll=1`). gh = gh-sim against local bare origins (no GitHub remote).
Evidence: `handoff/drill-evidence-build-supervisor/`.

| Scenario | Result | Evidence |
|---|---|---|
| (a) kill builder mid-phase | builder 15121 killed 15:26:06; DIED ntfy; new builder 19210 launched **121 s** after the kill (limit 240 s); auto directive "resume 1/2" | timeline.md, launches/launches-drill-a, plans/build-plan-drill-a.md |
| (b) scoped failure report | operator APPROVE; directive (awk total + regression test pinning 417.50, re-run phase 3 gates) written to plan; relaunched (launch 2, approvals 1) | plans/build-plan-drill-b.md, operator-logs/operator-log-drill-b.md |
| (c) PROTECTED (publish to Audrey's live "Best of Kitchen") | ESCALATED, ntfy priority 4 (high), one yes/no question, **no relaunch** (launch_count 1) | ntfy-poll-messages.tsv, registry/drill-c.json |
| (d) bad evidence | merge gate FAIL: row 7 99.99 vs source 52.25, total 452.00 vs 417.50, screenshot "ERROR 500"; rejection directive 1/2 + relaunch | plans/build-plan-drill-d.md, gate-drill-d.md |
| (e) good evidence | merge gate PASS (1 screenshot opened, 2 JSON parsed, 10 rows spot-checked), squash-merged onto drill origin main, queued drill-e2 launched | gate-drill-e.md, drill-re-origin-main.log, registry/drill-e2.json |

ntfy: **12 messages polled == 12 local sends (1:1)**, no feature repeated a state back-to-back (one ntfy per transition):
```
drill-a: RUNNING - builder pid 15121, active 0m ago
drill-b: STOPPED - failure-report-drill-b-phase-3.md; operator triage started
drill-c: STOPPED - failure-report-drill-c-phase-3.md; operator triage started
drill-d: DONE - PR #101 checks green; merge gate started
drill-e: DONE - PR #102 checks green; merge gate started
drill-c: ESCALATED - drill-c wants to publish and then delete 10 test rows on Audrey's live "Best of Kitchen" list ... yes/no?
drill-e: MERGED - PR #102 squash-merged by merge gate; launched next: drill-e2 (builder pid 17871)
drill-a: DIED - builder pid 15121 gone (or recycled), no new report; auto-resume starting
drill-b: RUNNING - approved fix 1, relaunched (builder pid 17444); builder pid 17444, active 0m ago
drill-d: RUNNING - merge-gate rejection 1/2, relaunched (builder pid 18171); builder pid 18171, active 0m ago
drill-e2: RUNNING - builder pid 17871, active 0m ago
drill-a: RUNNING - auto-resume 1/2 relaunched (builder pid 19210); builder pid 19210, active 0m ago
```
Earlier drill attempts (1-3) found real bugs, fixed before the final run (see phase-6 report).

## AC3 live install on the Mini (15:33 ET)
`./install-supervisor.sh` -> `~/Library/LaunchAgents/com.jimross.walkaway-supervisor.plist` (plutil OK), launchctl:
`run interval = 120 seconds`, `properties = runatload | abandon process group`, first run exit 0.
Adoption from launch logs: `adopted build-supervisor: builder 11000 (started Thu Nov 12 14:23:37 2026), watcher 11041`
(builder = PPID of logged watcher 11041); 10 logs skipped (dead watchers; review-page-v4 was already merged as PR #26 and its
processes were gone before install). First tick: `build-supervisor: LAUNCHED -> RUNNING - builder pid 11000`.
Real-topic ntfy poll: `{"id":"tXJ25yUdpEDJ","time":"20:33:32Z","priority":3,"message":"build-supervisor: RUNNING - builder pid 11000, active 0m ago"}`.
Evidence: `handoff/live-install-evidence-build-supervisor/`.

## AC4 `walkaway status` archived
`handoff/live-install-evidence-build-supervisor/walkaway-status.txt` (live) and `handoff/drill-evidence-build-supervisor/walkaway-status.txt` (drill, 6 builds across all states).

## AC5 protocol
`~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md` committed `82d2446` on bpo-comp-tool main (local, NOT pushed).

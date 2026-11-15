# Phase 5 report - supervisor-v3-data (tests, drill harness, installer, docs)

- **AC2 test coverage, all no-network** (fixture counts, time travel, stubbed triggers, stub operator or stub claude):
  - gap detection: missing D1 / short D2 / lag-aware D3 / weekday cadence D4 / CLOSED D5 / cache D6 / weekly D7 / errors D8 / real-incident fixtures D9 / supervisor gate + heartbeat + status D10;
  - retry window respected: D3, plus R2 (no new try inside verify_at);
  - re-pull cap: R2/R3, 2 tries then the operator, never a third;
  - escalation on no re-pull path: R7 -> O1 lost dates ESCALATED, O5 post-fix failure ESCALATED, O7 silent operator ESCALATED once;
  - Amazon guards: R4 business hours / CC batch / pacing, R5 the real cc noon window;
  - fix flow: O2-O4, plan with the hook contract -> merged -> hook re-pulls exactly the gap dates -> CLOSED, one ntfy per transition.
- **New regression R10** (found while writing the drill): after a fix merges, a gap the older path already failed must try the fix's hook first. `_method_for` now orders `requires_fix` methods first for `post_fix` gaps. Before the fix, R10 failed: the tick picked self-heal for age 2.
- **Robustness fixes** (found by O5/R10 in fresh homes): `_fire` and `data_fix_progress` create `$WALKAWAY_HOME/logs` before redirecting into it. A missing dir had turned every trigger into rc 1.
- **AC3 drill harness `tests/drill/run-data-drill.sh` (new):**
  - Real supervisor ticks with data watching on, a scratch home and time travel.
  - REAL `claude -p` diagnosis and REAL ntfy to a fresh drill topic, captured with the poll API.
  - Delete-free fixture series (drill-repull, drill-nopath, drill-lost) and a scratch owner repo whose pull fetches yesterday only.
  - A busy build holds the one-builder slot, so the fix plan only queues.
  - Expected ntfy: OPEN/CLOSED, OPEN/FIXING/CLOSED, OPEN/ESCALATED. Runs in Phase 6.
- **Installer:** `./install-supervisor.sh --data-on / --data-off`; `--uninstall` also removes data.enabled.
- **README:** data-series section (commands, states + ntfy table, re-pull paths and guards, operator, state/log paths). `.gitignore` adds tests/drill/work-data/.
- Gates: shellcheck 0; 272/272 (data-gaps 38, data-operator 25, data-repull 29, parse 7, states 18, v2-AC1 12, jobs-states 38, job-operator 37, operator 68).

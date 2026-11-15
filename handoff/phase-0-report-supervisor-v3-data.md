# Phase 0 report - supervisor-v3-data (prepare + inventory, read-only)

- Read: WALKAWAY_BUILD_PROTOCOL.md, build-plan-supervisor-v3-data.md, README.md, ROADMAP.md (this repo has no CLAUDE.md / TOOLCHAIN_OVERVIEW.md). Branch `feature/supervisor-v3-data` clean at bf81919. Host: the Mini (Jims-Mac-Mini.local).
- **The plan has no phase list, "Phase gates" or files budget.** Its 6 items map onto the protocol's phases:
  - P0 inventory (item 0, read-only): `handoff/supervisor-v3-data-evidence/phase0-inventory.{md,txt}` + `phase0-floors.tsv`
  - P1 `data/series.yaml` + read-only count engine `lib/data.sh` (check / dump / floors) -> AC1 dump
  - P2 gap detector + gap state machine (OPEN / REPULLING / CLOSED / FIXING / ESCALATED), 14-day lookback, retry window = ready_by (item 1)
  - P3 re-pull executor: run-now / http-cron / command / self-heal methods, Amazon guards (business hours, CC batch, pacing), 2 tries per gap per day, verify -> CLOSED (item 2)
  - P4 data operator (incident + template-v2 fix plan queued/launched, or ONE question; "lost dates" escalation; post-merge re-pull) + ntfy rules + heartbeat + supervisor hook (gated on `~/.walkaway-cli/data.enabled`) + `walkaway status` DATA table (items 3-5)
  - P5 tests (AC2) + AC3 drill harness, installer flag, README
  - P6 live smoke: AC1 dump, AC3 drill (drill ntfy topic), AC4 live 14-day gap report + real gap handling, AC5 reload + status
  - P7 Codex (cap 2) + evidence MANIFEST + PR + CI + build report LAST
- Gates (bash adaptation, same as v1/v2): `shellcheck -S warning` on every script = 0; every `tests/test-*.sh` green; git clean after the phase commit; phase report + build-log line. Baseline: shellcheck 0; parse 7/7, states 18/18, AC1-v2 12/12, jobs-states 38/38, job-operator 37/37, operator 68/68 (180/180).
- **Live-safety constraint (same as v2):** launchd `com.jimross.walkaway-supervisor` runs `lib/supervisor.sh` from THIS working tree every 120 s and supervises this build (pid 67150) and bf-daily-retry-fix (audrey-ops-platform). All new logic goes into NEW files (lib/data.sh, lib/data-operator.sh, data/series.yaml); the one-line tick/heartbeat/status hooks are gated on `~/.walkaway-cli/data.enabled`, which stays absent until Phase 6.
- Inventory: 49 scheduled pulls/crons/agents across both repos -> 21 watched dated series + 28 excluded with a reason (sends, actions covered by jobs.yaml, inbox/queue scans, repair crons, unregistered Inngest, uninstalled plist). Floors: structural constant or 50% of the 30-day median, computed from real rows.
- **Real gap found:** `pulse_bb_showings_daily` has no rows after obs_date 2026-11-08 (6 periods in the lookback). The ST URL trigger also re-pulls BB yesterday (`setBbPending(true)`); older BB dates have no scriptable path -> operator path (fix build adding a date-range hook, or one question).
- **No date-range run-now hook exists in either repo.** Existing paths: Showrunner run-now (`extension_report_state.run_now_requested_at`, pulls yesterday / D-2 for cc,spc before noon), the extension self-heal (tracking + spc, ages 2-8), connect/markable self-filling windows, cron GETs (meta-sync, pulse-daily-sync?ifMissing=1, pulse-macro, pulse-events-refresh, pulse-signals, pulse-market-health), the ST URL trigger (D-1..D-8). Gaps outside those ages go to the operator.
- Tools: shellcheck 0.11, jq (strftime %G%V OK), ruby stdlib YAML, gh, claude, codex. Supabase aggregates are disabled (PGRST123) -> counts use `Prefer: count=exact` + `Range: 0-0` (one GET per period).
- Next phase entry: none blocked.

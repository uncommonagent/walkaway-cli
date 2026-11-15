# Phase 4 report - supervisor-v3-data (data operator, ntfy, heartbeat, supervisor hook, DATA table)

- **lib/data-operator.sh (new).** Acts on gaps that data_act marks `need_operator`: no re-pull path for the gap's age, or a re-pull that failed twice. It reuses the job operator's read-only `claude -p` call, the repo-locked `_queue_or_launch` and the template-v2 conventions.
  1. **Lost data:** the source cannot re-pull a past period (`historical: "no"`) and no path exists. ESCALATED with priority high, no model call. The question names the dates and rows, e.g. `scratch-lost lost 2026-11-15, 2026-11-16 (0/4 rows): the source cannot re-pull a past day. Accept the loss, or fix the pull so it stops missing days?`
  2. **Post-fix failure:** a fix for the series merged and its hook re-pull failed twice. ESCALATED; no second fix loop.
  3. **Fix already in flight** (registered and not merged, or still queued): the gaps join it as FIXING. No new plan.
  4. **Otherwise:** one fix build per series per day. Read-only diagnosis, then either:
     - an incident `job-incident-<series>-<date>.md` and a template-v2 plan whose `## Date-range re-pull hook` section quotes the series' `fix_hook` contract verbatim, plus the supervisor's exact call (AC "ACH"); the plan is queued or launched in the owner repo (FIXING);
     - or ONE question (ESCALATED). The guards are the same as v2: protected, needs a live session, confidence below high, no what_to_build.
  - `progress`: once the fix build is MERGED, the FIXING gaps go back to OPEN with `post_fix`, and `hook_merged` enables the series' `requires_fix` method. data_act then re-pulls exactly the gap dates and the count confirms CLOSED.
- **templates/data-operator-prompt.md (new).** States that a re-pull is never protected. The fix to build is usually the date-range hook through the existing pull path; logins/sessions escalate.
- **Supervisor hand-off (lib/data.sh):**
  - `_data_spawn_operator` runs detached, once per set of gaps. If the operator exits without a decision on the same gaps, the next tick sends one ESCALATED; it never loops.
  - `data_fix_progress` runs every tick while a fix is in flight.
- **ntfy, one line per transition per series per tick:** OPEN, FIXING, CLOSED (rows before -> after, and via what), ESCALATED (priority high). REPULLING is silent.
  - The 09/13/17 heartbeat lists only series with open gaps.
  - lib/supervisor.sh gained a tick hook and a heartbeat hook, both gated on `$WALKAWAY_HOME/data.enabled` (absent live). The file was replaced atomically; the 12:00:24 live tick ran clean on the new file.
- **`walkaway status` prints the DATA table** (SERIES, LAST COMPLETE, OPEN GAPS, LAST ACTION) after JOBS.
- **Tests:**
  - tests/test-data-operator.sh (new, 25/25):
    - O1 lost dates -> ESCALATED, no model.
    - O2 fix plan with every template-v2 section and the hook contract verbatim, launched with registry + parse-plan checks.
    - O3 in flight. O4 merged -> hook fires once for exactly 11-08..11-09 -> CLOSED; OPEN 1 / FIXING 1 / CLOSED 1 / ESCALATED 0.
    - O5 post-fix failure -> ESCALATED with no model or plan. O6 model escalation. O7 a silent operator -> exactly one ESCALATED.
  - test-data-gaps D10 (supervisor gate, heartbeat, status table).
- **Incident during this phase (contained):**
  - test-data-gaps D9 uses the REAL series.yaml. Once the operator hook existed it spawned real read-only `claude -p` diagnoses (bb, cc) from a scratch WALKAWAY_HOME.
  - They were killed within about a minute, before any decision.
  - Verified: no fix-data branch or launch in either repo, real queue and registry untouched.
  - The detection and re-pull suites now stub the operator (`tests/fixtures/data/operator-stub.sh`). Only test-data-operator runs the real operator, and it uses a stub claude.
- Gates: shellcheck 0; 271/271 (data-gaps 38, data-operator 25, data-repull 28, parse 7, states 18, v2-AC1 12, jobs-states 38, job-operator 37, operator 68).

# Walkaway Build Plan: drill-a (DRILL - throwaway)

## RESUME DIRECTIVE (auto, resume 1/2, 2026-11-12 15:28 ET) - read first
The previous builder session ended without a build or failure report (DIED: builder pid 15121 gone (or recycled), no new report). Continue from handoff/build-log-drill-a.md and the newest phase report: do NOT redo committed phases; finish the first unfinished phase, then continue the plan. Any earlier RESUME DIRECTIVE not marked [DONE] still applies.

## Feature name
`drill-a`

## Branch name
`feature/drill-a`

## Goal
Throwaway drill build for the walkaway supervisor. Export data/source.csv as an audited summary.

## What to build
1. lib/export.sh: read data/source.csv, write rows.json (id, name, amount) and summary.json {rows, total}.

## Do NOT build
Anything else. No network calls, no real lists, no customer-facing sends.

## Acceptance criteria
- [ ] AC1 handoff/drill-evidence/rows.json has exactly the 10 rows of data/source.csv with identical id/name/amount.
- [ ] AC2 handoff/drill-evidence/summary.json has rows = 10 and total = the sum of the amount column of data/source.csv.
- [ ] AC3 handoff/drill-evidence/result.png shows "DRILL OK" and "10/10 rows match".
- [ ] AC4 PR CI green and handoff/codex-review-drill-a.md closed (no open P1).

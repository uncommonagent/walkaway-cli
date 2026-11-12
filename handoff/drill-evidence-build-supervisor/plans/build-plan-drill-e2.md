# Walkaway Build Plan: drill-e2 (DRILL - throwaway)

## Feature name
`drill-e2`

## Branch name
`feature/drill-e2`

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
- [ ] AC4 PR CI green and handoff/codex-review-drill-e2.md closed (no open P1).

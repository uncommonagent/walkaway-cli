# Walkaway Build Plan: drill-b (DRILL - throwaway)

## RESUME DIRECTIVE (auto, approved fix 1, 2026-11-12 15:26 ET) - read first
RESUME DIRECTIVE (operator, drill-b, phase 3)

What failed: phase 3 gate tests/test-export.sh scored 9/10. test_total expects 417.50 but lib/export.sh prints 417 because bash integer arithmetic drops the cents.

Fix (approved as proposed):
1. In lib/export.sh, compute the summary total with awk instead of bash arithmetic or bc. Skip the header row and split on commas, e.g. `awk -F, 'NR>1 {s += $3} END {printf "%.2f", s}' data/source.csv`. Write it into summary.json as a number, total = 417.50, with rows = 10. Keep the amount values in rows.json exactly as they appear in the source (10.25, 17.25, ...), not rounded or truncated.
2. Add a regression test to tests/test-export.sh that pins summary.json total = 417.50 and rows = 10 for data/source.csv, plus one row-level check that rows.json amounts keep their cents (e.g. id 1 -> 10.25). Do not loosen or delete test_total.
3. Do not touch any other files. No bc dependency, no network calls.

Re-run: the full phase 3 gate (tests/test-export.sh). It must pass 10/10 plus the new regression test. Archive the passing gate output in the phase 3 report.

Then continue the plan from the build log; do not redo committed phases.

## Feature name
`drill-b`

## Branch name
`feature/drill-b`

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
- [ ] AC4 PR CI green and handoff/codex-review-drill-b.md closed (no open P1).

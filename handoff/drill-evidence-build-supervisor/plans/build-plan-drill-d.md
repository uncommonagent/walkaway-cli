# Walkaway Build Plan: drill-d (DRILL - throwaway)

## RESUME DIRECTIVE (auto, merge-gate rejection 1/2, 2026-11-12 15:26 ET) - read first
RESUME DIRECTIVE - merge-gate rejection (drill-d, rejection 1)

The merge gate failed AC1, AC2 and AC3. The archived evidence doesn't match data/source.csv.

Findings:
1. AC1: handoff/drill-evidence/rows.json row id=7 has amount 99.99. data/source.csv row 7 is `7,item-7,52.25`.
2. AC2: handoff/drill-evidence/summary.json has total 452.00. The correct sum of the source.csv amount column is 417.50. The file also has `source`/`generated_at` fields that lib/export.sh never writes, so it was not produced by the deliverable.
3. AC3: handoff/drill-evidence/result.png shows "ERROR 500 / export failed: 9/10 rows match". It needs to show "DRILL OK" and "10/10 rows match".

Fix:
- Regenerate the evidence by running the deliverable from the repo root: `bash lib/export.sh handoff/drill-evidence`. Don't hand-edit rows.json or summary.json.
- Verify: rows.json has 10 rows identical to source.csv (id 7 = 52.25), and summary.json = {"rows": 10, "total": 417.50}. If either is wrong, fix lib/export.sh (in scope), not the evidence.
- Re-render result.png from the verified comparison. It must read "DRILL OK" and "10/10 rows match".
- Update handoff/drill-evidence/MANIFEST.md if anything changed.

Commit, push to PR #101, and confirm CI (drill-ci) is green. Update handoff/build-report-drill-d.md LAST with the real values (rows=10, total=417.50, 10/10 match). No Codex cycle.

## Feature name
`drill-d`

## Branch name
`feature/drill-d`

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
- [ ] AC4 PR CI green and handoff/codex-review-drill-d.md closed (no open P1).

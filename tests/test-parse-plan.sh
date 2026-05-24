#!/usr/bin/env bash
# Smoke test for lib/parse-plan.sh against real build plan fixtures.
# Exit 0 = all pass. Exit 1 = at least one failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE="${SCRIPT_DIR}/../lib/parse-plan.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ── fixture 1: BPO Phase 3 (infers REPO_PATH from file location) ──────────────
BPO_PLAN="${HOME}/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md"
echo "Fixture 1: BPO Phase 3"

if [[ ! -f "$BPO_PLAN" ]]; then
  echo "  SKIP: fixture not found at $BPO_PLAN"
else
  eval "$(bash "$PARSE" "$BPO_PLAN")"
  assert_eq "FEATURE_NAME" "bpo-j-phase-3"   "$FEATURE_NAME"
  assert_eq "BRANCH_NAME"  "feature/bpo-j-phase-3" "$BRANCH_NAME"
  assert_eq "REPO_PATH"    "${HOME}/Projects/Throughline/throughline-app" "$REPO_PATH"
fi

# ── fixture 2: walkaway-cli plan (has explicit ## Repo section) ───────────────
WALKAWAY_PLAN="${HOME}/Projects/walkaway-cli/handoff/build-plan-walkaway-cli.md"
echo "Fixture 2: walkaway-cli plan"

if [[ ! -f "$WALKAWAY_PLAN" ]]; then
  echo "  SKIP: fixture not found at $WALKAWAY_PLAN"
else
  eval "$(bash "$PARSE" "$WALKAWAY_PLAN")"
  assert_eq "FEATURE_NAME" "walkaway-cli" "$FEATURE_NAME"
  assert_eq "BRANCH_NAME"  "main"         "$BRANCH_NAME"
  # REPO_PATH from ## Repo section should be ~/Projects/walkaway-cli
  assert_eq "REPO_PATH"    "${HOME}/Projects/walkaway-cli" "$REPO_PATH"
fi

# ── fixture 3: error on missing file ─────────────────────────────────────────
echo "Fixture 3: missing file returns error"
if bash "$PARSE" "/tmp/nonexistent-plan-file.md" 2>/dev/null; then
  echo "  FAIL: expected non-zero exit for missing file"
  ((FAIL++))
else
  echo "  PASS: non-zero exit for missing file"
  ((PASS++))
fi

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

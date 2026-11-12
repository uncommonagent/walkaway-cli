#!/usr/bin/env bash
# Stub walkaway builder for drills (WALKAWAY_BUILDER_CMD). walkaway execs it in the scratch repo exactly
# like `claude --dangerously-skip-permissions <prompt>`, with FEATURE_NAME / BRANCH_NAME exported.
#
# Behavior per launch comes from .drill/modes-<feature> (one mode per line; launch N uses line N, the last
# line repeats):
#   work            append to the build log every 15s, forever (a builder mid-phase)
#   fail-scoped     write the failure report from .drill/failure-<feature>.md, then idle (like interactive claude)
#   complete-good   archive .drill/evidence-good/, open a PR (gh-sim), build report LAST, then idle
#   complete-bad    same with .drill/evidence-bad/
# Every launch is logged to .drill/launches-<feature> with the prompt's first line and any directive seen.

set -uo pipefail

feature="${FEATURE_NAME:?}"
branch="${BRANCH_NAME:?}"
repo="$(pwd)"
drill="$repo/.drill"
mkdir -p "$drill" handoff

count_file="$drill/launch-count-$feature"
n=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$count_file"
mode=$(sed -n "${n}p" "$drill/modes-$feature" 2>/dev/null)
[[ -z "$mode" ]] && mode=$(tail -1 "$drill/modes-$feature" 2>/dev/null)
mode=${mode:-work}

plan="handoff/build-plan-$feature.md"
directive=$(grep -m1 '^## RESUME DIRECTIVE' "$plan" 2>/dev/null || true)
printf '%s\tlaunch %s\tpid %s\tmode %s\tdirective: %s\n' "$(date '+%H:%M:%S')" "$n" "$$" "$mode" "${directive:-none}" >> "$drill/launches-$feature"

log() { printf -- '- %s stub builder (launch %s, pid %s): %s\n' "$(date '+%H:%M:%S')" "$n" "$$" "$1" >> "handoff/build-log-$feature.md"; }

idle() { while true; do sleep 30; done; }

sleep "${STUB_BUILDER_STARTUP_SECS:-3}"   # a real builder never reports in its launch second

case "$mode" in
  work)
    log "phase work started (mode work)"
    while true; do sleep 15; log "working"; done
    ;;
  fail-scoped|fail-protected)
    log "gate failed, writing failure report"
    cp "$drill/failure-$feature.md" "handoff/failure-report-$feature-phase-3.md"
    idle
    ;;
  complete-good|complete-bad)
    kind=${mode#complete-}
    log "phase 6 smoke archived ($kind evidence)"
    rm -rf "handoff/drill-evidence"
    mkdir -p handoff/drill-evidence
    cp -R "$drill/evidence-$kind/." handoff/drill-evidence/
    printf '# Codex review - %s\n\nCycle 1: no P1, no P2. Cycle cap respected. Closed.\n' "$feature" > "handoff/codex-review-$feature.md"
    git add handoff && git commit -qm "drill: $feature evidence ($kind)" && git push -q origin "$branch"
    "${WALKAWAY_GH_CMD:-gh}" pr create-sim "$branch" > /dev/null
    printf '# Build report - %s\n\nAll phases done. Evidence: handoff/drill-evidence/ (summary.json, rows.json, result.png). PR open, CI green.\n' "$feature" > "handoff/build-report-$feature.md"
    git add handoff && git commit -qm "drill: $feature build report" && git push -q origin "$branch"
    idle
    ;;
esac

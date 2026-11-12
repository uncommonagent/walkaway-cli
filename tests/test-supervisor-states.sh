#!/usr/bin/env bash
# AC1: supervisor state classification from fixture dirs (tests/fixtures/states/<case>/).
#
# Each fixture dir holds handoff/ files, pr.json (what `gh pr view` returns) and fixture.env:
#   EXPECT     expected state
#   PID        alive | dead | recycled   (recycled = live PID whose start time does not match the registry)
#   REG_STATE  state already in the registry
#   TOUCH      "<file>:<minutes relative to now>" mtimes to set; the build was launched 60 min ago
# Exit 0 = all pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUP="${SCRIPT_DIR}/../lib/supervisor.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/states"
PASS=0
FAIL=0
SEEN_STATES=""

WORK=$(mktemp -d)
sleep 600 &
ALIVE_PID=$!
( exit 0 ) &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null
trap 'kill "$ALIVE_PID" 2>/dev/null; rm -rf "$WORK"' EXIT

# gh stub: prints the fixture's pr.json
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
cat "$FIXTURE_PR_JSON"
EOF
chmod +x "$WORK/bin/gh"

_touch_rel() { # file minutes
  local ts
  ts=$(date -v"${2}"M +%Y%m%d%H%M.%S)
  touch -t "$ts" "$1"
}

for dir in "$FIXTURES"/*/; do
  name=$(basename "$dir")
  # shellcheck disable=SC1091
  EXPECT="" PID="" REG_STATE="" TOUCH=""
  # shellcheck source=/dev/null
  source "$dir/fixture.env"

  case_dir="$WORK/$name"
  home="$case_dir/home"
  repo="$case_dir/repo"
  mkdir -p "$home/registry" "$repo"
  cp -R "$dir/handoff" "$repo/handoff"
  # Default every fixture file to "before launch", then apply the case's mtimes.
  find "$repo/handoff" -type f -exec touch -t "$(date -v-120M +%Y%m%d%H%M.%S)" {} +
  for t in $TOUCH; do _touch_rel "$repo/${t%%:*}" "${t##*:}"; done

  case "$PID" in
    alive)    pid=$ALIVE_PID; started=$(ps -o lstart= -p "$ALIVE_PID" | sed 's/^ *//;s/ *$//') ;;
    dead)     pid=$DEAD_PID;  started="Thu Jan  1 00:00:00 2026" ;;
    recycled) pid=$ALIVE_PID; started="Thu Jan  1 00:00:00 2026" ;;
  esac
  launched=$(date -v-60M +%s)
  jq -n --arg repo "$repo" --argjson pid "$pid" --arg started "$started" --argjson launched "$launched" \
    --arg state "$REG_STATE" '{feature:"demo", repo:$repo, repo_root:$repo, plan:($repo+"/handoff/build-plan-demo.md"),
      branch:"feature/demo", builder_pid:$pid, builder_started:$started, watcher_pid:null,
      launched_epoch:$launched, state:$state, launch_count:1}' > "$home/registry/demo.json"

  got=$(WALKAWAY_HOME="$home" WALKAWAY_GH_CMD="$WORK/bin/gh" FIXTURE_PR_JSON="$dir/pr.json" \
        WALKAWAY_CLAUDE_PROJECTS="$WORK/no-transcripts" bash "$SUP" classify demo)
  state=${got%%$'\t'*}
  if [[ "$state" == "$EXPECT" ]]; then
    echo "  PASS: $name -> $state (${got#*$'\t'})"
    PASS=$((PASS + 1))
    SEEN_STATES+=" $state"
  else
    echo "  FAIL: $name expected $EXPECT, got: $got"
    FAIL=$((FAIL + 1))
  fi
done

# Every one of the 7 states must be covered by at least one passing fixture.
for s in RUNNING STALLED STOPPED DIED DONE MERGED ESCALATED; do
  if [[ " $SEEN_STATES " != *" $s "* ]]; then
    echo "  FAIL: no passing fixture for state $s"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

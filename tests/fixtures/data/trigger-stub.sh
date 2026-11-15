#!/usr/bin/env bash
# Re-pull trigger stub (WALKAWAY_DATA_TRIGGER_CMD) for tests and the AC3 drill.
#   trigger-stub.sh <series> <method> <arg> <from> <to>
# Appends one line to $WALKAWAY_HOME/triggers.log (and the resolved call to triggers-resolved.log). STUB_RC = exit
# code (default 0). STUB_LAND=<count> "lands" that many rows for every day from..to in the fixture counts
# ($WALKAWAY_DATA_FIXTURES/<series>.json), like a re-pull whose rows arrive before the verify tick.
set -uo pipefail
echo "$1 $2 $3 $4 $5" >> "${WALKAWAY_HOME}/triggers.log"
# The command / http path the supervisor would really call (dates substituted), when lib/data.sh passes it.
[[ -n "${WALKAWAY_DATA_TRIGGER_RESOLVED+x}" ]] && echo "$1 $2 $WALKAWAY_DATA_TRIGGER_RESOLVED" >> "${WALKAWAY_HOME}/triggers-resolved.log"
if [[ -n "${STUB_LAND:-}" && -n "${WALKAWAY_DATA_FIXTURES:-}" ]]; then
  python3 - "${WALKAWAY_DATA_FIXTURES}/$1.json" "$4" "$5" "$STUB_LAND" <<'PY'
import json, sys, datetime, os
p, a, b, c = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(p)) if os.path.exists(p) else {}
x = datetime.date.fromisoformat(a); e = datetime.date.fromisoformat(b)
while x <= e:
    d[x.isoformat()] = c; x += datetime.timedelta(days=1)
json.dump(d, open(p, "w"))
PY
fi
exit "${STUB_RC:-0}"

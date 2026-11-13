#!/usr/bin/env bash
# Scheduled-job watching for the walkaway supervisor (jobs.yaml at the repo root).
#
#   jobs.sh list                         one line per job: name, enabled, kind, days, retry_end, owner repo
#   jobs.sh check <job> [--date D]       run the job's read-only check for day D (ET, default today) -> JSON
#   jobs.sh dump [--out F] [job=D ...]   every enabled-or-named job's check with the queries, row counts and
#                                        sample rows it saw (AC2 evidence); job=D evaluates that job on day D
#
# Checks are READ-ONLY by construction: REST GETs only (no -X, no body, rpc/ refused) and log greps. The
# service-role key is read from the source's env file at call time and handed to curl on stdin (-K -), so it
# never appears in argv, logs or output.
#
# Test seams: WALKAWAY_JOBS_FILE (jobs.yaml), WALKAWAY_JOBS_REST_FIXTURES=<dir> (query <name> of job <job> is
# answered by <dir>/<job>/<name>.json instead of the network), WALKAWAY_JOBS_NOW (epoch "now").

set -uo pipefail

JOBS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALKAWAY_HOME="${WALKAWAY_HOME:-$HOME/.walkaway-cli}"
WALKAWAY_JOBS_FILE="${WALKAWAY_JOBS_FILE:-${JOBS_DIR}/../jobs.yaml}"
JOBS_TZ="America/New_York"

_jobs_now() { echo "${WALKAWAY_JOBS_NOW:-$(date +%s)}"; }

# ── config ───────────────────────────────────────────────────────────────────

# jobs.yaml as JSON (ruby stdlib YAML; no yq on the Mini).
jobs_config() {
  ruby -ryaml -rjson -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0])))' "$WALKAWAY_JOBS_FILE"
}

# jobs_get <config-json> <job> -> the job's JSON (empty if unknown)
jobs_get() { jq -c --arg n "$2" '.jobs[] | select(.name == $n)' <<< "$1"; }

jobs_names() { jq -r '.jobs[].name' <<< "$1"; }

_expand_home() { local p="$1"; echo "${p/#\~/$HOME}"; }

# ── time (all local ET) ──────────────────────────────────────────────────────

jobs_today() { TZ=$JOBS_TZ date -r "$(_jobs_now)" +%F; }
_day_shift() { TZ=$JOBS_TZ date -j -v"$2"d -f '%Y-%m-%d' "$1" +%F; }
_dow() { TZ=$JOBS_TZ date -j -f '%Y-%m-%d' "$1" +%a | tr '[:upper:]' '[:lower:]'; }
# _at <date> <HH:MM> -> epoch of that ET wall-clock time
_at() { TZ=$JOBS_TZ date -j -f '%Y-%m-%d %H:%M:%S' "$1 $2:00" +%s; }
_utc() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }

# jobs_runs_on <job-json> <date>: true if the job is scheduled that weekday.
jobs_runs_on() {
  local dow
  dow=$(_dow "$2")
  jq -e --arg d "$dow" '(.days // ["mon","tue","wed","thu","fri","sat","sun"]) | index($d) != null' <<< "$1" > /dev/null
}

# ── substitution ─────────────────────────────────────────────────────────────

# _ctx <config> <date> -> JSON of every placeholder value for that job day.
_ctx() {
  local cfg="$1" d="$2" now ds de eval_now
  now=$(_jobs_now)
  ds=$(_at "$d" 00:00); de=$(_at "$(_day_shift "$d" +1)" 00:00)
  # A past day is judged as of its end, today as of now.
  eval_now=$now; (( de < now )) && eval_now=$((de - 1))
  jq -c --arg date "$d" --arg y "$(_day_shift "$d" -1)" --arg ds "$(_utc "$ds")" --arg de "$(_utc "$de")" \
    --arg now "$(_utc "$eval_now")" --arg s26 "$(_utc $((eval_now - 26 * 3600)))" '
    (.vars // {}) + {date: $date, yesterday: $y, day_start_utc: $ds, day_end_utc: $de,
      now_utc: ($now | rtrimstr("Z")), since_26h_utc: ($s26 | rtrimstr("Z"))}' <<< "$cfg"
}

# _subst <template> <ctx-json>: replace every {key} with its value.
_subst() {
  local s="$1" k v
  while IFS=$'\t' read -r k v; do
    s=${s//\{$k\}/$v}
  done < <(jq -r 'to_entries[] | [.key, (.value | tostring)] | @tsv' <<< "$2")
  printf '%s' "$s"
}

# ── read-only sources ────────────────────────────────────────────────────────

_env_val() { # file var -> value (quotes stripped); never echoed by callers
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | sed -e "s/^[\"']//" -e "s/[\"']\$//" | tr -d '\r'
}

# _rest_get <config> <source> <job> <name> <path> -> JSON body (rows) or {"__error": "..."}
_rest_get() {
  local cfg="$1" src="$2" job="$3" name="$4" path="$5" s envf url key out code
  if [[ -n "${WALKAWAY_JOBS_REST_FIXTURES:-}" ]]; then
    local fx="${WALKAWAY_JOBS_REST_FIXTURES}/${job}/${name}.json"
    [[ -f "$fx" ]] && cat "$fx" || echo '[]'
    return 0
  fi
  case "$path" in rpc/*|*/rpc/*) echo '{"__error":"rpc refused: checks are read-only"}'; return 0 ;; esac
  s=$(jq -c --arg s "$src" '.sources[$s] // empty' <<< "$cfg")
  [[ -n "$s" ]] || { echo "{\"__error\":\"unknown source $src\"}"; return 0; }
  envf=$(_expand_home "$(jq -r '.env_file' <<< "$s")")
  url=$(_env_val "$envf" "$(jq -r '.url_var' <<< "$s")")
  key=$(_env_val "$envf" "$(jq -r '.key_var' <<< "$s")")
  [[ -n "$url" && -n "$key" ]] || { echo "{\"__error\":\"missing url/key vars in $envf\"}"; return 0; }
  out=$(mktemp)
  # GET only. The key goes to curl on stdin, never on the command line.
  code=$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$key" "$key" |
         curl -sS -g -m 25 -K - -o "$out" -w '%{http_code}' "$url/rest/v1/$path" 2>/dev/null) || code="curl-failed"
  if [[ "$code" == 2* ]] && jq -e 'type == "array"' "$out" > /dev/null 2>&1; then
    cat "$out"
  else
    jq -cn --arg c "$code" --arg b "$(head -c 300 "$out" 2>/dev/null)" '{__error: ("HTTP " + $c + " " + $b)}'
  fi
  rm -f "$out"
}

# _log_lines <path> <grep-ERE> -> JSON array of the last 20 matching lines ([] if the file is missing).
_log_lines() {
  local p
  p=$(_expand_home "$1")
  [[ -f "$p" ]] || { echo '[]'; return 0; }
  grep -E -- "$2" "$p" 2>/dev/null | tail -20 | jq -R . | jq -sc .
}

# _gather <config> <job-json> <ctx> <spec-key> -> {q: {name: rows}, log: {name: lines}, paths: {name: path}}
# spec-key is "check" or "diagnose".
_gather() {
  local cfg="$1" job="$2" ctx="$3" key="$4" name tpl path rows src jname q='{}' logs='{}' paths='{}'
  src=$(jq -r '.check.source' <<< "$job"); jname=$(jq -r '.name' <<< "$job")
  while IFS=$'\t' read -r name tpl; do
    [[ -n "$name" ]] || continue
    path=$(_subst "$tpl" "$ctx")
    rows=$(_rest_get "$cfg" "$src" "$jname" "$name" "$path")
    q=$(jq -c --arg n "$name" --argjson r "$rows" '. + {($n): $r}' <<< "$q")
    paths=$(jq -c --arg n "$name" --arg p "$path" '. + {($n): $p}' <<< "$paths")
  done < <(jq -r --arg k "$key" '(.[$k].queries // {}) | to_entries[] | [.key, .value] | @tsv' <<< "$job")
  local lpath lgrep
  while IFS=$'\t' read -r name lpath lgrep; do
    [[ -n "$name" ]] || continue
    lgrep=$(_subst "$lgrep" "$ctx")
    logs=$(jq -c --arg n "$name" --argjson l "$(_log_lines "$lpath" "$lgrep")" '. + {($n): $l}' <<< "$logs")
    paths=$(jq -c --arg n "log:$name" --arg p "$lpath ~ /$lgrep/" '. + {($n): $p}' <<< "$paths")
  done < <(jq -r --arg k "$key" '(.[$k].logs // {}) | to_entries[] | [.key, .value.path, .value.grep] | @tsv' <<< "$job")
  jq -cn --argjson q "$q" --argjson l "$logs" --argjson p "$paths" '{q: $q, log: $l, paths: $p}'
}

# jobs_check <config> <job> [date] -> {job, date, verdict, detail, checked_at, paths, rows, sample}
# verdict: ok | pending | retrying | failed (from the predicate) | error (a source failed; judged by nobody)
jobs_check() {
  local cfg="$1" name="$2" d="${3:-}" job ctx g pred res
  job=$(jobs_get "$cfg" "$name")
  [[ -n "$job" ]] || { jq -cn --arg j "$name" '{job: $j, verdict: "error", detail: "unknown job"}'; return 1; }
  [[ -n "$d" ]] || d=$(jobs_today)
  ctx=$(_ctx "$cfg" "$d")
  g=$(_gather "$cfg" "$job" "$ctx" check)
  pred=$(jq -r '.check.predicate' <<< "$job")
  if jq -e '[.q[] | objects | select(has("__error"))] | length > 0' <<< "$g" > /dev/null; then
    res=$(jq -c '{verdict: "error", detail: ([.q | to_entries[] | select(.value | type == "object") | "\(.key): \(.value.__error)"] | join("; "))}' <<< "$g")
  else
    res=$(jq -c --argjson c "$ctx" "(\$c + {q: .q, log: .log}) | $pred" <<< "$g" 2>&1) ||
      res=$(jq -cn --arg e "$res" '{verdict: "error", detail: ("predicate: " + $e)}')
    jq -e '.verdict | IN("ok","pending","retrying","failed")' <<< "$res" > /dev/null 2>&1 ||
      res=$(jq -cn --arg r "$res" '{verdict: "error", detail: ("predicate returned " + $r)}')
  fi
  jq -cn --arg j "$name" --arg d "$d" --arg at "$(_utc "$(_jobs_now)")" --argjson r "$res" --argjson g "$g" '
    {job: $j, date: $d, verdict: $r.verdict, detail: $r.detail, checked_at: $at, paths: $g.paths,
     rows: ([$g.q | to_entries[] | {key, value: (if (.value | type) == "array" then (.value | length) else -1 end)}] | from_entries),
     sample: ([$g.q | to_entries[] | {key, value: (if (.value | type) == "array" then .value[0:3] else .value end)}] | from_entries),
     log: $g.log}'
}

# jobs_diagnose <config> <job> <date> -> JSON of the job's diagnose queries + logs (read-only).
jobs_diagnose() {
  local cfg="$1" job ctx
  job=$(jobs_get "$cfg" "$2")
  ctx=$(_ctx "$cfg" "$3")
  _gather "$cfg" "$job" "$ctx" diagnose | jq -c '{queries: .paths, rows: .q, logs: .log}'
}

# ── dump (AC2) ───────────────────────────────────────────────────────────────

jobs_dump() {
  local cfg="$1"; shift
  local -a overrides=("$@")
  local name d o res
  echo "# jobs.yaml check dump - $(TZ=$JOBS_TZ date -r "$(_jobs_now)" '+%Y-%m-%d %H:%M %Z') (read-only REST GETs; keys never printed)"
  while IFS= read -r name; do
    d=""
    for o in "${overrides[@]+"${overrides[@]}"}"; do [[ "${o%%=*}" == "$name" ]] && d=${o#*=}; done
    [[ -z "$d" && "$(jq -r --arg n "$name" '.jobs[] | select(.name == $n) | .enabled' <<< "$cfg")" != "true" ]] && {
      printf '\n## %s - disabled in jobs.yaml (pass %s=<date> to check a past day)\n' "$name" "$name"; continue; }
    res=$(jobs_check "$cfg" "$name" "$d")
    printf '\n## %s (day %s) -> %s\n' "$name" "$(jq -r .date <<< "$res")" "$(jq -r .verdict <<< "$res" | tr '[:lower:]' '[:upper:]')"
    printf 'detail: %s\n' "$(jq -r .detail <<< "$res")"
    jq -r '.paths | to_entries[] | "query \(.key): \(.value)"' <<< "$res"
    jq -r '.rows | to_entries[] | "rows \(.key): \(.value)"' <<< "$res"
    jq -r '.sample | to_entries[] | "sample \(.key): \(.value | tostring | .[0:600])"' <<< "$res"
    jq -r '.log | to_entries[] | "log \(.key): \(.value | last // "(no matching line)")"' <<< "$res"
  done < <(jobs_names "$cfg")
}

jobs_list() {
  jq -r '.jobs[] | [.name, (if .enabled then "on" else "OFF" end), .kind, ((.days // ["daily"]) | join(",")),
    (.retry_end // "\(.retry_window_mins)m"), (if .protected then "protected" else "-" end), .owner_repo] | @tsv' <<< "$1" |
    column -t -s $'\t'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  cfg=$(jobs_config) || { echo "jobs: cannot parse $WALKAWAY_JOBS_FILE" >&2; exit 1; }
  case "$cmd" in
    list)  jobs_list "$cfg" ;;
    check)
      job="${1:?job}"; shift; d=""
      [[ "${1:-}" == "--date" ]] && d="${2:?date}"
      jobs_check "$cfg" "$job" "$d" | jq .
      ;;
    dump)
      out=""
      [[ "${1:-}" == "--out" ]] && { out="${2:?file}"; shift 2; }
      if [[ -n "$out" ]]; then jobs_dump "$cfg" "$@" > "$out"; echo "wrote $out"; else jobs_dump "$cfg" "$@"; fi
      ;;
    *) echo "Usage: jobs.sh list | check <job> [--date YYYY-MM-DD] | dump [--out F] [job=YYYY-MM-DD ...]" >&2; exit 1 ;;
  esac
fi

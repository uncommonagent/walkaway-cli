#!/usr/bin/env bash
# Data-series gap watching for the walkaway supervisor (data/series.yaml at the repo root).
#
#   data.sh list                          one line per entry: name, watch, cadence, table.key, floor, re-pull methods
#   data.sh check <series> [--as-of T]    read-only: per-period row counts over the lookback -> JSON (gaps, last complete)
#   data.sh dump [--out F] [--as-of T] [series=T ...]
#                                         every entry: watched series' checks (queries, counts, gaps) and excluded
#                                         entries' reason + probe row (AC1 evidence); series=T checks that one as of T
#   data.sh floors                        re-derive each watched floor from the last 30 days / 8 weeks / 3 months
#   data.sh inventory-diff <ids-file>     names in the inventory file vs series.yaml (both directions)
#   data.sh tick                          evaluate every watched series: gap transitions, re-pulls (supervisor)
#   data.sh evaluate <series>             one series' tick
#   data.sh status | heartbeat            DATA table (walkaway status) | heartbeat lines for open gaps
#   data.sh state <series>                the series' gap state file
#
# T = "YYYY-MM-DD HH:MM" (ET) or an epoch. Counts are READ-ONLY: one REST GET per period with Prefer: count=exact and
# Range: 0-0 (aggregates are disabled on both projects). The service-role key is read from the source's env file at
# call time and handed to curl on stdin (-K -), never in argv, logs or output.
#
# Test seams: WALKAWAY_DATA_FILE (series.yaml), WALKAWAY_DATA_NOW (epoch "now"), WALKAWAY_DATA_FIXTURES=<dir>
# (period counts of series <s> come from <dir>/<s>.json {"<period anchor>": count}; missing anchor = 0; a key
# "__error" = every count errors), WALKAWAY_DATA_COUNT_LOG=<file> (one line per period counted).

set -uo pipefail

DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# jobs.sh brings the ET time helpers, _subst, _expand_home, _env_val and the read-only _rest_get.
# shellcheck source=lib/jobs.sh
source "${DATA_DIR}/jobs.sh"
WALKAWAY_DATA_FILE="${WALKAWAY_DATA_FILE:-${DATA_DIR}/../data/series.yaml}"

_data_now() { echo "${WALKAWAY_DATA_NOW:-$(date +%s)}"; }

# ── config ───────────────────────────────────────────────────────────────────

data_config() {
  ruby -ryaml -rjson -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0])))' "$WALKAWAY_DATA_FILE"
}

# data_get <config> <series> -> the entry's JSON with defaults applied (empty if unknown)
data_get() {
  jq -c --arg n "$2" '.defaults as $d | .series[] | select(.name == $n)
    | . + {lookback_days: (.lookback_days // $d.lookback_days // 14), lookback_weeks: (.lookback_weeks // $d.lookback_weeks // 4),
           lookback_months: (.lookback_months // $d.lookback_months // 2),
           max_tries_per_day: (.max_tries_per_day // $d.max_tries_per_day // 2)}' <<< "$1"
}

data_watched() { jq -r '.series[] | select(.watch == true) | .name' <<< "$1"; }
data_names() { jq -r '.series[].name' <<< "$1"; }

# ── periods (all local ET) ───────────────────────────────────────────────────
# A period is named by its anchor date: the day (daily), the Monday (weekly) or the 1st (monthly). Age = how many
# periods before the current one (0 = the current day/week/month).

data_today() { TZ=$JOBS_TZ date -r "$(_data_now)" +%F; }

# _anchor_of <cadence> <date> -> the anchor of the period containing date
_anchor_of() {
  local u
  case "$1" in
    weekly)  u=$(TZ=$JOBS_TZ date -j -f '%Y-%m-%d' "$2" +%u); _day_shift "$2" "-$((u - 1))" ;;
    monthly) echo "${2:0:8}01" ;;
    *)       echo "$2" ;;
  esac
}

# _anchor_back <cadence> <anchor> <k> -> anchor k periods earlier (k may be negative = later)
_anchor_back() {
  local k="$3" s
  case "$1" in
    weekly)  s=$(( -7 * k )) ;;
    monthly) if (( k >= 0 )); then TZ=$JOBS_TZ date -j -v-"${k}"m -f '%Y-%m-%d' "$2" +%F; else TZ=$JOBS_TZ date -j -v+"$(( -k ))"m -f '%Y-%m-%d' "$2" +%F; fi; return ;;
    *)       s=$(( -k )) ;;
  esac
  if (( s >= 0 )); then _day_shift "$2" "+$s"; else _day_shift "$2" "$s"; fi
}

# _period_key <key-type> <anchor> -> the value the key column holds for that period (date / ISO yearweek)
_period_key() {
  case "$1" in
    yearweek) TZ=$JOBS_TZ date -j -f '%Y-%m-%d' "$2" +%G%V ;;
    *)        echo "$2" ;;
  esac
}

# _ready_at <series-json> <anchor> -> epoch the period must be complete by (anchor + lag_days at ready_by)
_ready_at() {
  local lag rb
  lag=$(jq -r '.lag_days // 0' <<< "$1"); rb=$(jq -r '.ready_by // "00:00"' <<< "$1")
  _at "$(_day_shift "$2" "+$lag")" "$rb"
}

# _periods <series-json> -> TSV lines "age<TAB>anchor" over the lookback, newest first
_periods() {
  local s="$1" cad n cur k
  cad=$(jq -r '.cadence // "daily"' <<< "$s")
  case "$cad" in
    weekly)  n=$(jq -r '.lookback_weeks' <<< "$s") ;;
    monthly) n=$(jq -r '.lookback_months' <<< "$s") ;;
    *)       n=$(jq -r '.lookback_days' <<< "$s") ;;
  esac
  cur=$(_anchor_of "$cad" "$(data_today)")
  local days a
  days=$(jq -c '.days // empty' <<< "$s")
  for (( k = 0; k <= n; k++ )); do
    a=$(_anchor_back "$cad" "$cur" "$k")
    # Weekday cadence (days: [mon..fri]): a daily period on an unscheduled weekday is not expected at all.
    [[ -n "$days" && "$cad" == "daily" ]] && ! jq -e --arg d "$(_dow "$a")" 'index($d) != null' <<< "$days" > /dev/null && continue
    printf '%s\t%s\n' "$k" "$a"
  done
}

# _extra_periods <series-json> <anchors-json> -> "age<TAB>anchor" for listed anchors OLDER than the lookback (a gap
# still being re-pulled or fixed stays counted after it ages out of the lookback)
_extra_periods() {
  [[ -n "${2:-}" ]] || return 0
  local oldest a
  oldest=$(_periods "$1" | tail -1 | cut -f2)
  while IFS= read -r a; do
    [[ -n "$a" && "$a" < "$oldest" ]] && printf '%s\t%s\n' "$(_age_of "$1" "$a")" "$a"
  done < <(jq -r '.[]' <<< "$2" | sort -ru)
  return 0
}

# _age_of <series-json> <anchor> -> periods between anchor and the current period
_age_of() {
  local s="$1" cad cur k
  cad=$(jq -r '.cadence // "daily"' <<< "$s")
  cur=$(_anchor_of "$cad" "$(data_today)")
  case "$cad" in
    monthly) echo $(( (10#${cur:0:4} - 10#${2:0:4}) * 12 + 10#${cur:5:2} - 10#${2:5:2} )) ;;
    weekly)  k=$(( ( $(_at "$cur" 12:00) - $(_at "$2" 12:00) ) / 86400 )); echo $(( (k + 3) / 7 )) ;;
    *)       echo $(( ( $(_at "$cur" 12:00) - $(_at "$2" 12:00) + 43200 ) / 86400 )) ;;
  esac
}

# ── read-only counts ─────────────────────────────────────────────────────────

# _data_ctx <config> -> placeholder JSON (vars + today)
_data_ctx() { jq -c --arg t "$(data_today)" '(.vars // {}) + {today: $t}' <<< "$1"; }

# _count_path <series-json> <anchor> <ctx> -> PostgREST path counting that period's rows
_count_path() {
  local s="$1" a="$2" col typ f kf cad nxt
  col=$(jq -r '.key.column' <<< "$s"); typ=$(jq -r '.key.type // "date"' <<< "$s"); cad=$(jq -r '.cadence // "daily"' <<< "$s")
  case "$typ" in
    timestamp)
      nxt=$(_anchor_back "$cad" "$a" -1)
      kf="$col=gte.$(_utc "$(_at "$a" 00:00)")&$col=lt.$(_utc "$(_at "$nxt" 00:00)")" ;;
    *) kf="$col=eq.$(_period_key "$typ" "$a")" ;;
  esac
  f=$(_subst "$(jq -r '.filters // ""' <<< "$s")" "$3")
  printf '%s?select=%s%s&%s' "$(jq -r .table <<< "$s")" "$col" "${f:+&$f}" "$kf"
}

# _source_conn <config> <source> -> "url<TAB>key" (never printed by callers)
_source_conn() {
  local s envf
  s=$(jq -c --arg s "$2" '.sources[$s] // empty' <<< "$1")
  [[ -n "$s" ]] || return 1
  envf=$(_expand_home "$(jq -r '.env_file' <<< "$s")")
  printf '%s\t%s\n' "$(_env_val "$envf" "$(jq -r '.url_var' <<< "$s")")" "$(_env_val "$envf" "$(jq -r '.key_var' <<< "$s")")"
}

# _rest_count <config> <source> <path> -> row count, or "E:<message>"
_rest_count() {
  local conn url key hdr code range
  conn=$(_source_conn "$1" "$2") || { echo "E:unknown source $2"; return 0; }
  url=${conn%%$'\t'*}; key=${conn#*$'\t'}
  [[ -n "$url" && -n "$key" ]] || { echo "E:missing url/key vars for $2"; return 0; }
  hdr=$(mktemp)
  # GET only (the request has no body and no -X). The key goes to curl on stdin, never on the command line.
  code=$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\nheader = "Prefer: count=exact"\nheader = "Range: 0-0"\n' "$key" "$key" |
         curl -sS -g -m 25 -K - -D "$hdr" -o /dev/null -w '%{http_code}' "$url/rest/v1/$3" 2>/dev/null) || code="curl-failed"
  range=$(tr -d '\r' < "$hdr" | sed -n 's/^[Cc]ontent-[Rr]ange: *//p' | tail -1)
  rm -f "$hdr"
  if [[ "$code" == 2* && "$range" == */* && "${range##*/}" =~ ^[0-9]+$ ]]; then
    echo "${range##*/}"
  else
    echo "E:HTTP $code ${range:-no content-range}"
  fi
}

# _count <config> <series-json> <anchor> <ctx> -> count or "E:..."
_count() {
  local cfg="$1" s="$2" a="$3" name fx
  name=$(jq -r .name <<< "$s")
  [[ -n "${WALKAWAY_DATA_COUNT_LOG:-}" ]] && echo "$name $a" >> "$WALKAWAY_DATA_COUNT_LOG"
  if [[ -n "${WALKAWAY_DATA_FIXTURES:-}" ]]; then
    fx="${WALKAWAY_DATA_FIXTURES}/${name}.json"
    if [[ -f "$fx" ]] && jq -e 'has("__error")' "$fx" > /dev/null 2>&1; then echo "E:$(jq -r .__error "$fx")"; return 0; fi
    [[ -f "$fx" ]] && jq -r --arg a "$a" '.[$a] // 0' "$fx" || echo 0
    return 0
  fi
  _rest_count "$cfg" "$(jq -r .source <<< "$s")" "$(_count_path "$s" "$a" "$4")"
}

# ── check ────────────────────────────────────────────────────────────────────

# data_check <config> <series> [selection-json] -> JSON
#   selection {skip: [anchors], extra: [anchors]}: skip = known complete, not re-counted ("skipped"); extra = anchors
#   counted even when older than the lookback (tracked gaps). No selection = every ready lookback period.
#   {series, as_of, checked_at, floor, periods: [{period, key, age, ready_at, ready, count, status, query}],
#    gaps: [{period, count, status}], last_complete, errors}
# status: not_ready (period's ready_by not reached: not counted) | ok (>= floor) | short (0 < count < floor) |
#         missing (0) | error (the count failed) | skipped (not in only-anchors: known complete, not re-counted)
data_check() {
  local cfg="$1" name="$2" only="${3:-}" s ctx now tmp age a ra key rows=() i=0
  s=$(data_get "$cfg" "$name")
  [[ -n "$s" ]] || { jq -cn --arg n "$name" '{series: $n, error: "unknown series"}'; return 1; }
  ctx=$(_data_ctx "$cfg"); now=$(_data_now); tmp=$(mktemp -d)
  while IFS=$'\t' read -r age a; do
    ra=$(_ready_at "$s" "$a"); key=$(_period_key "$(jq -r '.key.type // "date"' <<< "$s")" "$a")
    rows+=("$age"$'\t'"$a"$'\t'"$ra"$'\t'"$key")
    if (( ra <= now )) && { [[ -z "$only" ]] || ! jq -e --arg a "$a" '(.skip // []) | index($a) != null' <<< "$only" > /dev/null; }; then
      ( _count "$cfg" "$s" "$a" "$ctx" > "$tmp/$i" ) &
    fi
    i=$((i + 1))
  done < <(_periods "$s"; [[ -n "$only" ]] && _extra_periods "$s" "$(jq -c '.extra // []' <<< "$only")")
  wait
  local floor out='[]' c st q
  floor=$(jq -r '.floor // 1' <<< "$s"); i=0
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r age a ra key <<< "$row"
    q=$(_count_path "$s" "$a" "$ctx")
    if (( ra > now )); then st=not_ready; c=null
    elif [[ ! -f "$tmp/$i" ]]; then st=skipped; c=null
    else
      c=$(cat "$tmp/$i")
      if [[ "$c" == E:* ]]; then st=error; c=$(jq -cn --arg e "${c#E:}" '$e')
      elif (( c >= floor )); then st=ok
      elif (( c > 0 )); then st=short
      else st=missing; fi
    fi
    out=$(jq -c --arg a "$a" --arg k "$key" --argjson age "$age" --arg ra "$(_utc "$ra")" --argjson ready "$( (( ra <= now )) && echo true || echo false )" \
            --argjson c "$c" --arg st "$st" --arg q "$q" \
            '. + [{period: $a, key: $k, age: $age, ready_at: $ra, ready: $ready, count: $c, status: $st, query: $q}]' <<< "$out")
    i=$((i + 1))
  done
  rm -rf "$tmp"
  jq -cn --arg n "$name" --arg asof "$(TZ=$JOBS_TZ date -r "$now" '+%Y-%m-%d %H:%M %Z')" --arg at "$(_utc "$now")" \
    --argjson f "$floor" --argjson p "$out" '
    {series: $n, as_of: $asof, checked_at: $at, floor: $f, periods: $p,
     gaps: [$p[] | select(.status == "short" or .status == "missing") | {period, count, status}],
     errors: [$p[] | select(.status == "error") | {period, error: .count}],
     last_complete: ([$p[] | select(.status == "ok") | .period] | max)}'
}

# ── dump (AC1) ───────────────────────────────────────────────────────────────

# _as_of_epoch <"YYYY-MM-DD HH:MM" | epoch> -> epoch
_as_of_epoch() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || TZ=$JOBS_TZ date -j -f '%Y-%m-%d %H:%M' "$1" +%s; }

data_dump() {
  local cfg="$1"; shift
  local -a overrides=("$@")
  local name s w res o t ctx
  ctx=$(_data_ctx "$cfg")
  echo "# data/series.yaml check dump - $(TZ=$JOBS_TZ date -r "$(_data_now)" '+%Y-%m-%d %H:%M %Z') (read-only REST GETs, exact counts; keys never printed)"
  while IFS= read -r name; do
    s=$(data_get "$cfg" "$name"); w=$(jq -r '.watch' <<< "$s")
    if [[ "$w" != "true" ]]; then
      printf '\n## %s - EXCLUDED: %s (covered by: %s)\n' "$name" "$(jq -r .reason <<< "$s")" "$(jq -r '.covered_by // "-"' <<< "$s")"
      if jq -e '.probe' <<< "$s" > /dev/null; then
        local pq rows
        pq=$(_subst "$(jq -r .probe.query <<< "$s")" "$ctx")
        rows=$(_rest_get "$cfg" "$(jq -r .probe.source <<< "$s")" "$name" probe "$pq")
        printf 'probe: %s\nprobe row: %s\n' "$pq" "$(jq -c '.[0] // .' <<< "$rows" | cut -c1-400)"
      fi
      continue
    fi
    t=""
    for o in "${overrides[@]+"${overrides[@]}"}"; do [[ "${o%%=*}" == "$name" ]] && t=${o#*=}; done
    if [[ -n "$t" ]]; then
      res=$(WALKAWAY_DATA_NOW=$(_as_of_epoch "$t") data_check "$cfg" "$name")
    else
      res=$(data_check "$cfg" "$name")
    fi
    printf '\n## %s (as of %s) -> %s\n' "$name" "$(jq -r .as_of <<< "$res")" \
      "$(jq -r 'if (.errors | length) > 0 then "ERROR" elif (.gaps | length) > 0 then "GAPS \(.gaps | length)" else "PASS" end' <<< "$res")"
    printf 'table: %s.%s (%s, %s)  floor: %s (%s)  last complete: %s\n' "$(jq -r .table <<< "$s")" "$(jq -r .key.column <<< "$s")" \
      "$(jq -r .key.type <<< "$s")" "$(jq -r .cadence <<< "$s")" "$(jq -r .floor <<< "$s")" "$(jq -r .floor_basis <<< "$s")" "$(jq -r '.last_complete // "-"' <<< "$res")"
    printf 'query (newest period): %s\n' "$(jq -r '[.periods[] | select(.ready)][0].query // .periods[0].query' <<< "$res")"
    jq -r '.periods[] | "  \(.period) key=\(.key) age=\(.age) \(.status)\(if .count != null then " rows=\(.count)" else "" end)"' <<< "$res"
    jq -r 'if (.gaps | length) > 0 then "gaps: " + ([.gaps[] | "\(.period) (\(.status) \(.count))"] | join(", ")) else empty end' <<< "$res"
  done < <(data_names "$cfg")
}

# ── floors (re-derive from real rows) ────────────────────────────────────────

data_floors() {
  local cfg="$1" name s cad n cur k a ctx tmp vals med uniq f
  ctx=$(_data_ctx "$cfg")
  printf 'SERIES\tPERIODS\tMIN..MAX\tMEDIAN\tFORMULA\tYAML\tMATCH\n'
  while IFS= read -r name; do
    s=$(data_get "$cfg" "$name"); cad=$(jq -r .cadence <<< "$s")
    case "$cad" in weekly) n=8 ;; monthly) n=3 ;; *) n=30 ;; esac
    cur=$(_anchor_of "$cad" "$(data_today)"); tmp=$(mktemp -d)
    # the n most recent READY periods
    k=0; local got=0
    while (( got < n && k < n + 20 )); do
      a=$(_anchor_back "$cad" "$cur" "$k")
      if (( $(_ready_at "$s" "$a") <= $(_data_now) )); then ( _count "$cfg" "$s" "$a" "$ctx" > "$tmp/$a" ) & got=$((got + 1)); fi
      k=$((k + 1))
    done
    wait
    vals=$(cat "$tmp"/* 2>/dev/null | grep -E '^[0-9]+$' | awk '$1 > 0' | sort -n)
    rm -rf "$tmp"
    n=$(grep -c . <<< "$vals"); uniq=$(sort -u <<< "$vals" | grep -c .)
    med=$(awk '{a[NR]=$1} END {if (NR == 0) print 0; else if (NR % 2) print a[(NR+1)/2]; else print int((a[NR/2]+a[NR/2+1])/2)}' <<< "$vals")
    if (( uniq == 1 )); then f=$med; else f=$(( med / 2 )); (( f < 1 )) && f=1; fi
    printf '%s\t%s\t%s..%s\t%s\t%s\t%s\t%s\n' "$name" "$n" "$(head -1 <<< "$vals")" "$(tail -1 <<< "$vals")" "$med" "$f" \
      "$(jq -r .floor <<< "$s")" "$( [[ "$f" == "$(jq -r .floor <<< "$s")" ]] && echo yes || echo "differs: Phase 0 window (see floor_basis)")"
  done < <(data_watched "$cfg")
}

# ── gap state machine ────────────────────────────────────────────────────────
#
# One state file per series: $WALKAWAY_HOME/data/state/<series>.json
#   {series, gaps: {<period>: GAP}, ok_periods: [...], full_scan_date, last_complete, last_action, checked_at,
#    error_ticks, fix_feature, fix_plan, fix_date, fix_merged, operator_pid, operator_spawned, incident}
# GAP = {state, status (missing|short), opened_at, rows_before, rows_now, failed_tries, tries_today, tries_day,
#        last_try {at, method, label, rc}, verify_at, need_operator, reason, closed_at, rows_after, closed_via}
# Gap states (per period):
#   OPEN       rows missing/under the floor past the period's ready_by (the series' own retries are done)   ntfy (grouped)
#   REPULLING  a re-pull fired (or a self-heal wait started); verified at verify_at                       silent
#   CLOSED     rows at/above the floor (verified by a count)                                              ntfy (grouped)
#   FIXING     no re-pull path / re-pull failed twice: the data operator queued a fix build               ntfy
#   ESCALATED  one question for Jim (lost dates, protected cause, unclear)                                ntfy high
# A period is complete when its count reaches the floor; complete periods are cached (ok_periods) and re-counted
# only on the first tick of each local day (full scan), so a normal tick costs one GET per open gap or new period.

WALKAWAY_DATA_ERROR_TICKS="${WALKAWAY_DATA_ERROR_TICKS:-15}"

_dstate_dir() { echo "${WALKAWAY_HOME}/data/state"; }
_dstate_file() { echo "$(_dstate_dir)/$1.json"; }
dstate_get() { local f; f=$(_dstate_file "$1"); [[ -f "$f" ]] && jq -r "$2 // empty" "$f"; }
dstate_json() { local f; f=$(_dstate_file "$1"); [[ -f "$f" ]] && cat "$f" || jq -cn --arg s "$1" '{series: $s, gaps: {}, ok_periods: []}'; }

# dstate_update <series> <jq-filter> [jq args...]  (atomic; creates the file if missing)
dstate_update() {
  local s="$1" filter="$2" f tmp
  shift 2
  f=$(_dstate_file "$s"); mkdir -p "$(_dstate_dir)"
  [[ -f "$f" ]] || jq -n --arg s "$s" '{series: $s, gaps: {}, ok_periods: []}' > "$f"
  tmp="${f}.tmp.$$"
  jq "$@" "$filter" "$f" > "$tmp" && mv "$tmp" "$f"
}

_dlog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] data: $*"; }
_dnotify() { # line [priority]
  # shellcheck source=lib/notify.sh
  source "${DATA_DIR}/notify.sh"
  notify_line "$1" "${2:-default}"
}

# _dates_label <periods...> -> "2026-11-09..11-13" for a consecutive daily run, else a comma list
_dates_label() {
  local -a p=("$@")
  (( ${#p[@]} == 0 )) && return 0
  (( ${#p[@]} == 1 )) && { echo "${p[0]}"; return 0; }
  if (( ${#p[@]} > 2 )) && [[ "$(_day_shift "${p[0]}" "+$(( ${#p[@]} - 1 ))")" == "${p[${#p[@]}-1]}" ]]; then
    echo "${p[0]}..${p[${#p[@]}-1]:5}"
  else
    local IFS=,; echo "${p[*]}" | sed 's/,/, /g'
  fi
}

# data_gap_transition <series> <new-state> <action> <periods...>
# Moves the listed gaps to new-state and records the series' last action. ntfy: one line per call (the caller
# groups a series' periods per tick) for OPEN, CLOSED, FIXING and ESCALATED (priority high); REPULLING is silent.
data_gap_transition() {
  local s="$1" new="$2" action="$3" now
  shift 3
  (( $# > 0 )) || return 0
  now=$(_data_now)
  dstate_update "$s" '
    reduce $ps[] as $p (.; .gaps[$p] = ((.gaps[$p] // {}) + {state: $st, since: ($now|tonumber)}))
    | .last_action = $a' --arg st "$new" --arg a "$action" --arg now "$now" --argjson ps "$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  _dlog "$s: $(_dates_label "$@") -> $new - $action"
  case "$new" in
    OPEN|CLOSED|FIXING) _dnotify "data $s: $new - $action" ;;
    ESCALATED)          _dnotify "data $s: ESCALATED - $action" high ;;
  esac
}

# _gap_status_line <count> <floor> -> "missing (0/10 rows)" | "short (4/10 rows)"
_gap_word() { (( $1 > 0 )) && echo "short ($1/$2 rows)" || echo "missing (0/$2 rows)"; }

# data_detect <config> <series> -> applies OPEN / CLOSED transitions from one count pass; prints nothing
data_detect() {
  local cfg="$1" name="$2" s st today full only res floor
  s=$(data_get "$cfg" "$name"); st=$(dstate_json "$name"); today=$(data_today)
  floor=$(jq -r '.floor // 1' <<< "$s")
  full=0
  [[ "$(jq -r '.full_scan_date // ""' <<< "$st")" != "$today" || "${WALKAWAY_DATA_FULL:-}" == "1" ]] && full=1
  # Full scan: every ready lookback period. Otherwise skip the periods known complete. Always count every tracked
  # non-CLOSED gap, also one older than the lookback.
  only=$(jq -c --argjson full "$full" '{skip: (if $full == 1 then [] else (.ok_periods // []) end),
           extra: [.gaps | to_entries[] | select(.value.state != "CLOSED") | .key]}' <<< "$st")
  res=$(data_check "$cfg" "$name" "$only")
  [[ -n "$res" ]] || return 1
  dstate_update "$name" '.checked_at = ($n|tonumber)' --arg n "$(_data_now)"

  # Count errors: never judged; a long run of them escalates once.
  if jq -e '(.errors | length) > 0' <<< "$res" > /dev/null; then
    local n
    n=$(( $(dstate_get "$name" .error_ticks || echo 0) + 1 ))
    dstate_update "$name" '.error_ticks = ($n|tonumber) | .last_action = $a' --arg n "$n" \
      --arg a "count error ($n): $(jq -r '.errors[0] | "\(.period): \(.error)"' <<< "$res" | cut -c1-120)"
    if (( n == WALKAWAY_DATA_ERROR_TICKS )); then
      dstate_update "$name" '.error_escalated = true'
      _dnotify "data $name: ESCALATED - the $name row count has failed $n ticks in a row ($(jq -r '.errors[0].error' <<< "$res" | cut -c1-100)). Look at the check or the source?" high
    fi
  else
    dstate_update "$name" '.error_ticks = 0 | del(.error_escalated)'
  fi

  # Periods counted this pass.
  local counted opened=() closed=() p c gst word=""
  counted=$(jq -c '[.periods[] | select(.status == "ok" or .status == "short" or .status == "missing")]' <<< "$res")
  while IFS=$'\t' read -r p c; do
    [[ -n "$p" ]] || continue
    gst=$(jq -r --arg p "$p" '.gaps[$p].state // ""' <<< "$st")
    if (( c >= floor )); then
      dstate_update "$name" '.ok_periods = ((.ok_periods // []) + [$p] | unique) | if .gaps[$p] then .gaps[$p].rows_now = ($c|tonumber) else . end' --arg p "$p" --arg c "$c"
      if [[ -n "$gst" && "$gst" != "CLOSED" ]]; then
        dstate_update "$name" '.gaps[$p] += {rows_after: ($c|tonumber), closed_at: ($n|tonumber), closed_via: (.gaps[$p].last_try.label // "rows landed (no re-pull by the supervisor)")}' \
          --arg p "$p" --arg c "$c" --arg n "$(_data_now)"
        closed+=("$p")
      fi
    else
      dstate_update "$name" '.ok_periods = ((.ok_periods // []) - [$p]) | if .gaps[$p] then .gaps[$p].rows_now = ($c|tonumber) | .gaps[$p].status = $w else . end' \
        --arg p "$p" --arg c "$c" --arg w "$( (( c > 0 )) && echo short || echo missing)"
      if [[ -z "$gst" || "$gst" == "CLOSED" ]]; then
        dstate_update "$name" '.gaps[$p] = {state: "NEW", status: $w, opened_at: ($n|tonumber), rows_before: ($c|tonumber), rows_now: ($c|tonumber),
            failed_tries: 0, tries_today: 0, tries_day: $d}' \
          --arg p "$p" --arg c "$c" --arg w "$( (( c > 0 )) && echo short || echo missing)" --arg n "$(_data_now)" --arg d "$today"
        opened+=("$p")
      fi
    fi
  done < <(jq -r '.[] | [.period, .count] | @tsv' <<< "$counted" | sort)

  if (( ${#opened[@]} > 0 )); then
    local cs
    cs=$(jq -c --argjson ps "$(printf '%s\n' "${opened[@]}" | jq -R . | jq -sc .)" '[.periods[] | select(.period as $x | $ps | index($x))] | sort_by(.period) | map(.count)' <<< "$res")
    if jq -e 'max == 0' <<< "$cs" > /dev/null; then word="missing (0/$floor rows)"
    elif jq -e 'length == 1' <<< "$cs" > /dev/null; then word="short ($(jq -r '.[0]' <<< "$cs")/$floor rows)"
    else word="under floor $floor (rows: $(jq -r 'join(", ")' <<< "$cs"))"; fi
    data_gap_transition "$name" OPEN "$(_dates_label "${opened[@]}") $word" "${opened[@]}"
  fi
  if (( ${#closed[@]} > 0 )); then
    local parts
    parts=$(jq -r --argjson ps "$(printf '%s\n' "${closed[@]}" | jq -R . | jq -sc .)" '
      [.gaps | to_entries[] | select(.key as $k | $ps | index($k)) | "\(.key) rows \(.value.rows_before) -> \(.value.rows_after)"] | join(", ")' "$(_dstate_file "$name")")
    data_gap_transition "$name" CLOSED "$parts (floor $floor; via $(dstate_get "$name" ".gaps[\"${closed[0]}\"].closed_via"))" "${closed[@]}"
  fi

  # Bookkeeping: last complete period, full-scan stamp, prune caches outside the lookback.
  local oldest
  oldest=$(_periods "$s" | tail -1 | cut -f2)
  dstate_update "$name" '
      .last_complete = ([(.last_complete // ""), $lc] | max | if . == "" then null else . end)
    | (if $full == "1" then .full_scan_date = $t else . end)
    | .ok_periods = [(.ok_periods // [])[] | select(. >= $o)]
    | .gaps = (.gaps | with_entries(select(.value.state != "CLOSED" or .key >= $o)))
    | if ([.gaps[] | select(.state != "CLOSED")] | length) == 0 and ((.last_action // "") == "" or ((.last_action // "") | startswith("no gaps")))
      then .last_action = "no gaps (checked " + $hm + ")" else . end' \
    --arg lc "$(jq -r '.last_complete // ""' <<< "$res")" --arg full "$full" --arg t "$today" --arg o "$oldest" --arg hm "$(_hhmm_now)"
}

# ── re-pull (plan item 2) ────────────────────────────────────────────────────
#
# For every OPEN gap: pick the first repull method that covers the gap's age (and, for run-now cc/spc, the local
# hour), check its guard, fire it once for all gaps it covers this tick (from = oldest, to = newest), and verify
# at verify_at: rows at/above the floor -> CLOSED (data_detect), else the try failed -> OPEN again. Max
# max_tries_per_day tries per gap per local day; a guard deferral (business hours, CC batch, pacing) is not a try.
# Two failed tries, or no method covering the gap's age, hands the gap to the data operator (lib/data-operator.sh:
# fix build or one question). A method marked requires_fix is the date-range hook a fix build adds: used only
# after that fix merged (.fix_merged).
#
# Triggers (the series' own pull paths only):
#   run_now   PATCH extension_report_state SET run_now_requested_at = now WHERE user_id = <audrey_user> AND
#             report_type = <one allow-listed base type>: exactly what the Showrunner run-now route writes
#   http      GET <app_url><path> with Authorization: Bearer <cron secret>, read from the env file at call time and
#             handed to curl on stdin (never argv/logs)
#   command   the series' fixed local command ({from}/{to} substituted; ISO dates only)
#   self_heal nothing fires: the series refills itself; the try is the wait until verify_at
# Test seam: WALKAWAY_DATA_TRIGGER_CMD=<script> replaces every trigger: called as <script> <series> <method>
# <arg> <from> <to>; its exit code is the trigger's rc. WALKAWAY_DATA_GUARD_FIXTURE=<file> answers the CC-batch query.

WALKAWAY_DATA_RUN_NOW_TYPES="tracking_offsite tracking_onsite bounty cc spc connect_summary"
WALKAWAY_DATA_HTTP_TIMEOUT="${WALKAWAY_DATA_HTTP_TIMEOUT:-60}"

_drepull_log() { mkdir -p "${WALKAWAY_HOME}/logs"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${WALKAWAY_HOME}/logs/data-repull.log"; }

# _hhmm_now -> local HH:MM of "now"
_hhmm_now() { TZ=$JOBS_TZ date -r "$(_data_now)" +%H:%M; }

# _amazon_guard <config> -> "" when an Amazon trigger may fire now, else the reason to wait
_amazon_guard() {
  local cfg="$1" g hs he now last pace rows
  g=$(jq -c '.guards.amazon // {}' <<< "$cfg")
  hs=$(jq -r '.business_hours.start // "09:00"' <<< "$g"); he=$(jq -r '.business_hours.end // "19:00"' <<< "$g")
  now=$(_hhmm_now)
  if [[ "$now" < "$hs" || ! "$now" < "$he" ]]; then echo "outside Amazon business hours $hs-$he"; return 0; fi
  last=$(cat "${WALKAWAY_HOME}/data/state/_amazon_last_trigger" 2>/dev/null || echo 0)
  pace=$(( $(jq -r '.pace_mins // 15' <<< "$g") * 60 ))
  if (( $(_data_now) - last < pace )); then echo "paced: last Amazon trigger $(( ($(_data_now) - last) / 60 ))m ago (one per $((pace / 60))m)"; return 0; fi
  if [[ -n "${WALKAWAY_DATA_GUARD_FIXTURE:-}" ]]; then
    rows=$(cat "$WALKAWAY_DATA_GUARD_FIXTURE")
  else
    rows=$(_rest_get "$cfg" "$(jq -r '.cc_batch.source' <<< "$g")" data-guard cc_batch "$(_subst "$(jq -r '.cc_batch.query' <<< "$g")" "$(_data_ctx "$cfg")")")
  fi
  if jq -e 'type == "object"' <<< "$rows" > /dev/null 2>&1; then echo "CC batch check failed ($(jq -r '.__error // "error"' <<< "$rows" | cut -c1-80))"; return 0; fi
  if jq -e "$(jq -r '.cc_batch.predicate' <<< "$g")" <<< "$rows" > /dev/null 2>&1; then echo "CC batch in flight"; return 0; fi
  return 0
}

# _rows_guard <config> <guard-name> -> "" when the guard's read-only query returns at least one row, else its wait
# reason. Used for side effects of a re-pull path that must never fire a send (e.g. the ST daily ingest sends the
# day's Pulse brief if it has not gone out yet: the ST URL trigger only fires once today's brief exists).
_rows_guard() {
  local cfg="$1" g rows
  g=$(jq -c --arg n "$2" '.guards[$n] // empty' <<< "$cfg")
  [[ -n "$g" ]] || { echo "unknown guard $2"; return 0; }
  if [[ -n "${WALKAWAY_DATA_GUARD_FIXTURE:-}" ]]; then
    rows=$(cat "${WALKAWAY_DATA_GUARD_FIXTURE%.json}.$2.json" 2>/dev/null || echo '[{"fixture":"default-pass"}]')
  else
    rows=$(_rest_get "$cfg" "$(jq -r '.source' <<< "$g")" data-guard "$2" "$(_subst "$(jq -r '.query' <<< "$g")" "$(_data_ctx "$cfg")")")
  fi
  if jq -e 'type == "array" and length > 0' <<< "$rows" > /dev/null 2>&1; then return 0; fi
  if jq -e 'type == "object"' <<< "$rows" > /dev/null 2>&1; then echo "$2 check failed ($(jq -r '.__error // "error"' <<< "$rows" | cut -c1-80))"; return 0; fi
  jq -r '.wait_reason // "guard \(.)"' <<< "$g"
}

# _method_for <config> <series-json> <age> <hook_merged> [post_fix] -> "go <idx>" | "wait <reason>" | "none"
# A post_fix gap (its fix build merged) tries the fix's date-range hook first: the older paths already failed it.
_method_for() {
  local cfg="$1" s="$2" age="$3" fixed="$4" post="${5:-false}" i m h0 h1 now wait="" g order
  now=$(_hhmm_now)
  if [[ "$post" == "true" ]]; then
    order=$(jq -r '(.repull // []) | to_entries | (map(select(.value.requires_fix == true)) + map(select(.value.requires_fix != true))) | .[].key' <<< "$s")
  else
    order=$(jq -r '(.repull // []) | keys[]' <<< "$s")
  fi
  for i in $order; do
    m=$(jq -c --argjson i "$i" '.repull[$i]' <<< "$s")
    [[ "$(jq -r '.requires_fix // false' <<< "$m")" == "true" && "$fixed" != "true" ]] && continue
    jq -e --argjson a "$age" '.ages == "all" or ((.ages // []) | index($a) != null)' <<< "$m" > /dev/null || continue
    if jq -e '.hours' <<< "$m" > /dev/null; then
      h0=$(jq -r '.hours[0]' <<< "$m"); h1=$(jq -r '.hours[1]' <<< "$m")
      if [[ "$now" < "$h0" ]]; then wait=${wait:-"$(jq -r .method <<< "$m") window opens $h0"}; continue; fi
      [[ "$now" < "$h1" || "$h1" == "24:00" ]] || continue
    fi
    case "$(jq -r '.guard // ""' <<< "$m")" in
      "") g="" ;;
      amazon) g=$(_amazon_guard "$cfg") ;;
      *) g=$(_rows_guard "$cfg" "$(jq -r '.guard' <<< "$m")") ;;
    esac
    if [[ -n "$g" ]]; then wait=${wait:-$g}; continue; fi
    echo "go $i"; return 0
  done
  [[ -n "$wait" ]] && { echo "wait $wait"; return 0; }
  echo "none"
}

# _method_label <method-json> -> short human label
_method_label() {
  jq -r 'if .method == "run_now" then "run-now \(.report_type)"
         elif .method == "http" then "GET \(.path)"
         elif .method == "self_heal" then "self-heal wait"
         else "command" + (if .requires_fix then " (fix hook)" else "" end) + ": " + (.command | .[0:90]) end' <<< "$1"
}

# _run_now <config> <series-json> <report_type> -> rc 0 if exactly one state row was stamped
_run_now() {
  local cfg="$1" s="$2" rt="$3" conn url key out code ctx user
  [[ " $WALKAWAY_DATA_RUN_NOW_TYPES " == *" $rt "* ]] || { _drepull_log "run_now refused: $rt not allow-listed"; return 2; }
  ctx=$(_data_ctx "$cfg"); user=$(jq -r '.audrey_user // ""' <<< "$ctx")
  [[ "$user" =~ ^[0-9a-f-]{36}$ ]] || { _drepull_log "run_now refused: no audrey_user"; return 2; }
  conn=$(_source_conn "$cfg" "$(jq -r .source <<< "$s")") || return 2
  url=${conn%%$'\t'*}; key=${conn#*$'\t'}
  out=$(mktemp)
  code=$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nheader = "Prefer: return=representation"\n' "$key" "$key" |
         curl -sS -g -m 25 -K - -X PATCH -o "$out" -w '%{http_code}' \
           --data "{\"run_now_requested_at\":\"$(_utc "$(_data_now)")\"}" \
           "$url/rest/v1/extension_report_state?user_id=eq.${user}&report_type=eq.${rt}&select=report_type,run_now_requested_at" 2>/dev/null) || code=curl-failed
  _drepull_log "run_now $rt -> HTTP $code $(head -c 200 "$out")"
  if [[ "$code" == 2* ]] && [[ "$(jq 'length' "$out" 2>/dev/null)" == 1 ]]; then rm -f "$out"; return 0; fi
  rm -f "$out"; return 1
}

# _http_get <config> <series-json> <path> -> rc 0 on 2xx (or a still-running request past the timeout)
_http_get() {
  local cfg="$1" s="$2" path="$3" src envf base secret out code
  src=$(jq -c --arg s "$(jq -r .source <<< "$s")" '.sources[$s]' <<< "$cfg")
  base=$(jq -r '.app_url' <<< "$src"); envf=$(_expand_home "$(jq -r '.env_file' <<< "$src")")
  secret=$(_env_val "$envf" "$(jq -r '.cron_secret_var' <<< "$src")")
  [[ -n "$secret" ]] || { _drepull_log "http $path refused: no cron secret"; return 2; }
  local crc=0
  out=$(mktemp)
  code=$(printf 'header = "Authorization: Bearer %s"\n' "$secret" |
         curl -sS -g -m "$WALKAWAY_DATA_HTTP_TIMEOUT" -K - -o "$out" -w '%{http_code}' "$base$path" 2>/dev/null) || crc=$?
  _drepull_log "http GET $base$path -> HTTP ${code:-none} (curl exit $crc) $(head -c 300 "$out" | tr '\n' ' ')"
  rm -f "$out"
  [[ "$code" == 2* ]] && return 0
  # curl exit 28 = our client timeout: the request was delivered and the route keeps running server-side (long
  # syncs, ~43 s cold starts): the verify step decides. Any other curl failure never reached the route: a failed try.
  (( crc == 28 )) && return 0
  return 1
}

# _fire <config> <series-json> <idx> <from> <to> -> rc of the trigger
_fire() {
  local cfg="$1" s="$2" i="$3" from="$4" to="$5" m method arg name cmd rc=0
  m=$(jq -c --argjson i "$i" '.repull[$i]' <<< "$s"); method=$(jq -r .method <<< "$m"); name=$(jq -r .name <<< "$s")
  arg=$(jq -r '.report_type // .path // .command // ""' <<< "$m")
  [[ "$from" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$to" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 2
  mkdir -p "${WALKAWAY_HOME}/logs"
  if [[ -n "${WALKAWAY_DATA_TRIGGER_CMD:-}" ]]; then
    "$WALKAWAY_DATA_TRIGGER_CMD" "$name" "$method" "$arg" "$from" "$to" >> "${WALKAWAY_HOME}/logs/data-repull.log" 2>&1 || rc=$?
    _drepull_log "$name: stub $method $arg $from..$to rc=$rc"
  else
    case "$method" in
      run_now)   _run_now "$cfg" "$s" "$arg" || rc=$? ;;
      http)      _http_get "$cfg" "$s" "$arg" || rc=$? ;;
      command)
        cmd=${arg//\{from\}/$from}; cmd=${cmd//\{to\}/$to}
        _drepull_log "$name: command $cmd"
        bash -c "$cmd" >> "${WALKAWAY_HOME}/logs/data-repull.log" 2>&1 & local p=$! w=0
        while kill -0 "$p" 2>/dev/null && (( w < 30 )); do sleep 1; w=$((w + 1)); done
        kill -0 "$p" 2>/dev/null && { kill "$p" 2>/dev/null; rc=124; } || { wait "$p"; rc=$?; } ;;
      self_heal) _drepull_log "$name: self-heal wait $from..$to" ;;
      *) rc=2 ;;
    esac
  fi
  if [[ "$(jq -r '.guard // ""' <<< "$m")" == "amazon" ]]; then
    mkdir -p "${WALKAWAY_HOME}/data/state"; _data_now > "${WALKAWAY_HOME}/data/state/_amazon_last_trigger"
  fi
  return "$rc"
}

# data_act <config> <series>: verify due tries, fire re-pulls for OPEN gaps, hand the rest to the data operator.
data_act() {
  local cfg="$1" name="$2" s st today now max fixed
  s=$(data_get "$cfg" "$name"); today=$(data_today); now=$(_data_now)
  max=$(jq -r '.max_tries_per_day' <<< "$s")
  if _data_operator_alive "$name"; then
    dstate_update "$name" '.last_action = "data operator running"'; return 0
  fi
  if [[ -n "$(dstate_get "$name" .fix_feature)" && "$(dstate_get "$name" .fix_merged)" != "true" ]]; then
    data_fix_progress "$cfg" "$name"
  fi
  # requires_fix hooks are enabled once any fix build for this series merged (the hook then exists in the owner repo).
  fixed=$(dstate_get "$name" .hook_merged); fixed=${fixed:-false}

  # 1. Verify: a REPULLING gap past verify_at whose rows did not land (detect ran first this tick) = a failed try.
  local p failed=()
  while IFS= read -r p; do [[ -n "$p" ]] && failed+=("$p"); done < <(jq -r --argjson n "$now" '
      .gaps | to_entries[] | select(.value.state == "REPULLING" and (.value.verify_at // 0) <= $n) | .key' "$(_dstate_file "$name")")
  if (( ${#failed[@]} > 0 )); then
    dstate_update "$name" 'reduce $ps[] as $p (.; .gaps[$p].failed_tries += 1 | .gaps[$p].state = "OPEN" | .gaps[$p].since = ($n|tonumber))
        | .last_action = $a' --argjson ps "$(printf '%s\n' "${failed[@]}" | jq -R . | jq -sc .)" --arg n "$now" \
      --arg a "re-pull did not land rows for $(_dates_label "${failed[@]}") ($(jq -r --arg p "${failed[0]}" '.gaps[$p] | "\(.last_try.label): rows \(.rows_now)"' "$(_dstate_file "$name")")/$(jq -r .floor <<< "$s"))"
    _dlog "$name: $(_dates_label "${failed[@]}") try failed (rows below floor at verify)"
  fi

  # 2. Plan this tick: per OPEN gap -> fire group / wait / operator.
  local -a groups=() handoff=()
  local waits="" age dec gi reason
  st=$(dstate_json "$name")
  while IFS=$'\t' read -r p; do
    [[ -n "$p" ]] || continue
    local g ft td tday
    g=$(jq -c --arg p "$p" '.gaps[$p]' <<< "$st")
    [[ "$(jq -r '.need_operator // false' <<< "$g")" == "true" ]] && continue
    ft=$(jq -r '.failed_tries // 0' <<< "$g"); tday=$(jq -r '.tries_day // ""' <<< "$g"); td=$(jq -r '.tries_today // 0' <<< "$g")
    [[ "$tday" != "$today" ]] && { td=0; dstate_update "$name" '.gaps[$p].tries_today = 0 | .gaps[$p].tries_day = $d' --arg p "$p" --arg d "$today"; }
    if (( ft >= 2 )); then
      handoff+=("$p"); dstate_update "$name" '.gaps[$p].need_operator = true | .gaps[$p].reason = $r' --arg p "$p" \
        --arg r "re-pull failed twice ($(jq -r '.last_try.label // "-"' <<< "$g"))"
      continue
    fi
    if (( td >= max )); then waits+="${p:5}: $max tries today; "; continue; fi
    age=$(_age_of "$s" "$p")
    dec=$(_method_for "$cfg" "$s" "$age" "$fixed" "$(jq -r '.post_fix // false' <<< "$g")")
    case "$dec" in
      go\ *)  gi=${dec#go }; groups+=("$gi"$'\t'"$p") ;;
      wait\ *) waits+="${p:5}: ${dec#wait }; " ;;
      none)
        handoff+=("$p")
        reason="no re-pull path for age $age$( [[ "$(jq -r '.historical' <<< "$s")" == "no" ]] && echo " (source cannot re-pull a past period)")"
        dstate_update "$name" '.gaps[$p].need_operator = true | .gaps[$p].reason = $r' --arg p "$p" --arg r "$reason" ;;
    esac
  done < <(jq -r '.gaps | to_entries[] | select(.value.state == "OPEN") | .key' <<< "$st" | sort)

  # 3. Fire each chosen method once for all of its gaps.
  local idx m label from to rc ps
  while IFS= read -r idx; do
    [[ -n "$idx" ]] || continue
    ps=$(printf '%s\n' "${groups[@]}" | awk -F'\t' -v i="$idx" '$1 == i {print $2}' | sort)
    from=$(head -1 <<< "$ps"); to=$(tail -1 <<< "$ps")
    m=$(jq -c --argjson i "$idx" '.repull[$i]' <<< "$s"); label=$(_method_label "$m")
    rc=0; _fire "$cfg" "$s" "$idx" "$from" "$to" || rc=$?
    local pj va
    pj=$(jq -R . <<< "$ps" | jq -sc .)
    va=$(( now + $(jq -r '.verify_after_mins // 30' <<< "$m") * 60 ))
    if (( rc == 0 )); then
      dstate_update "$name" 'reduce $ps[] as $p (.; .gaps[$p].tries_today += 1 | .gaps[$p].tries_day = $d
          | .gaps[$p].last_try = {at: ($n|tonumber), method: $m, label: $l, rc: 0} | .gaps[$p].verify_at = ($va|tonumber))' \
        --argjson ps "$pj" --arg d "$today" --arg n "$now" --arg m "$(jq -r .method <<< "$m")" --arg l "$label" --arg va "$va"
      # shellcheck disable=SC2046  # one period per word
      data_gap_transition "$name" REPULLING "re-pull $(_dates_label $(tr '\n' ' ' <<< "$ps")) via $label; verify $(TZ=$JOBS_TZ date -r "$va" +%H:%M)" $(tr '\n' ' ' <<< "$ps")
      _drepull_log "$name: fired $label for $from..$to (rows before: $(jq -r --argjson ps "$pj" '[.gaps | to_entries[] | select(.key as $k | $ps | index($k)) | "\(.key)=\(.value.rows_now)"] | join(" ")' "$(_dstate_file "$name")"))"
    else
      dstate_update "$name" 'reduce $ps[] as $p (.; .gaps[$p].tries_today += 1 | .gaps[$p].tries_day = $d | .gaps[$p].failed_tries += 1
          | .gaps[$p].last_try = {at: ($n|tonumber), method: $m, label: $l, rc: ($rc|tonumber)}) | .last_action = $a' \
        --argjson ps "$pj" --arg d "$today" --arg n "$now" --arg m "$(jq -r .method <<< "$m")" --arg l "$label" --arg rc "$rc" \
        --arg a "re-pull trigger failed (rc $rc): $label"
      _dlog "$name: trigger failed rc=$rc $label"
    fi
  done < <(printf '%s\n' "${groups[@]+"${groups[@]}"}" | cut -f1 | grep . | sort -un)

  [[ -n "$waits" ]] && (( ${#groups[@]} == 0 )) && dstate_update "$name" '.last_action = $a' --arg a "waiting: ${waits%; }"

  # 4. Gaps no re-pull can close (flagged this tick or earlier): the data operator decides (fix build or one question).
  (( ${#handoff[@]} > 0 )) && _dlog "$name: $(_dates_label "${handoff[@]}") -> data operator"
  _data_spawn_operator "$name"
  return 0
}

# ── data operator hand-off (plan item 3) ─────────────────────────────────────

_data_operator_alive() { local p; p=$(dstate_get "$1" .operator_pid); [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; }

# _data_spawn_operator <series>: detached data-operator.sh diagnose for the gaps marked need_operator. If it already
# ran for exactly these gaps and left them unresolved, never loop: escalate once.
_data_spawn_operator() {
  local name="$1" op="${WALKAWAY_DATA_OPERATOR:-${DATA_DIR}/data-operator.sh}" gaps prev log
  [[ -f "$op" ]] || return 0
  _data_operator_alive "$name" && return 0
  gaps=$(jq -c '[.gaps | to_entries[] | select(.value.state == "OPEN" and .value.need_operator == true) | .key] | sort' "$(_dstate_file "$name")")
  [[ "$gaps" == "[]" ]] && return 0
  prev=$(dstate_get "$name" .operator_gaps)
  if [[ "$prev" == "$gaps" ]]; then
    # shellcheck disable=SC2046  # one period per word
    data_gap_transition "$name" ESCALATED "Data operator exited without a decision on $name $(_dates_label $(jq -r '.[]' <<< "$gaps")). How should these gaps be handled?" $(jq -r '.[]' <<< "$gaps")
    return 0
  fi
  log="${WALKAWAY_HOME}/logs/data-operator-${name}.log"; mkdir -p "${WALKAWAY_HOME}/logs"
  nohup bash "$op" diagnose "$name" >> "$log" 2>&1 < /dev/null &
  local p=$!
  disown "$p" 2>/dev/null || true
  dstate_update "$name" '.operator_pid = ($p|tonumber) | .operator_gaps = $g | .last_action = $a' --arg p "$p" --arg g "$gaps" \
    --arg a "data operator diagnosing $(jq -r 'join(", ")' <<< "$gaps")"
}

# data_fix_progress <config> <series>: follow the series' fix build (data-operator.sh progress).
data_fix_progress() {
  local op="${WALKAWAY_DATA_OPERATOR:-${DATA_DIR}/data-operator.sh}"
  mkdir -p "${WALKAWAY_HOME}/logs"
  [[ -f "$op" ]] && bash "$op" progress "$2" >> "${WALKAWAY_HOME}/logs/data-operator-$2.log" 2>&1
  return 0
}

# data_evaluate <config> <series>: one series per tick: detect (counts -> OPEN / CLOSED), then act on open gaps.
data_evaluate() {
  local cfg="$1" name="$2"
  data_detect "$cfg" "$name" || { _dlog "$name: detect error"; return 1; }
  data_act "$cfg" "$name"
  return 0
}

# One pass over every watched series (called from the supervisor tick while $WALKAWAY_HOME/data.enabled exists).
data_tick() {
  local cfg name
  cfg=$(data_config) || { _dlog "cannot parse $WALKAWAY_DATA_FILE"; return 1; }
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    data_evaluate "$cfg" "$name" || _dlog "$name: evaluate error"
  done < <(data_watched "$cfg")
}

# Heartbeat lines: one per series with open (non-CLOSED) gaps.
data_heartbeat_lines() {
  local cfg name
  cfg=$(data_config) || return 0
  while IFS= read -r name; do
    [[ -f "$(_dstate_file "$name")" ]] || continue
    jq -r '[.gaps | to_entries[] | select(.value.state != "CLOSED")] as $g
      | if ($g | length) == 0 then empty else
          "data \(.series): \($g | length) open gap(s) " + ([$g[] | "\(.key) \(.value.state)"] | join(", ")) + " - \(.last_action // "-")"
        end' "$(_dstate_file "$name")"
  done < <(data_watched "$cfg")
}

# DATA table for `walkaway status`.
data_status() {
  local cfg name f
  cfg=$(data_config) || { echo "DATA: cannot parse $WALKAWAY_DATA_FILE"; return 0; }
  echo ""
  echo "DATA ($(data_today), data watching $( [[ -f "${WALKAWAY_HOME}/data.enabled" ]] && echo on || echo OFF))"
  {
    printf 'SERIES\tLAST COMPLETE\tOPEN GAPS\tLAST ACTION\n'
    while IFS= read -r name; do
      f=$(_dstate_file "$name")
      if [[ -f "$f" ]]; then
        jq -r '[.series, (.last_complete // "-"),
                ([.gaps | to_entries[] | select(.value.state != "CLOSED") | "\(.key[5:]) \(.value.state)"] | if length == 0 then "-" else join(", ") end),
                ((.last_action // "-") | .[0:100])] | @tsv' "$f"
      else
        printf '%s\t-\t-\tnot checked yet\n' "$name"
      fi
    done < <(data_watched "$cfg")
  } | column -t -s $'\t'
}

data_list() {
  jq -r '.series[] | [.name, (if .watch then "watch" else "excluded" end), (.cadence // "-"),
    (if .table then "\(.table).\(.key.column)" else "-" end), ((.floor // "-") | tostring),
    (if .watch then (((.repull // []) | map(.method + (if .requires_fix then "(fix)" else "" end)) | join(",")) | if . == "" then "none" else . end) else (.covered_by // "-") end)] | @tsv' <<< "$1" |
    column -t -s $'\t'
}

data_inventory_diff() {
  local cfg="$1" ids="$2"
  diff <(grep -v '^#' "$ids" | grep . | sort -u) <(data_names "$cfg" | sort -u)
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  cfg=$(data_config) || { echo "data: cannot parse $WALKAWAY_DATA_FILE" >&2; exit 1; }
  asof=""
  case "$cmd" in
    list)  data_list "$cfg" ;;
    check)
      s="${1:?series}"; shift
      [[ "${1:-}" == "--as-of" ]] && asof=$(_as_of_epoch "${2:?time}")
      WALKAWAY_DATA_NOW="${asof:-${WALKAWAY_DATA_NOW:-}}" data_check "$cfg" "$s" | jq .
      ;;
    dump)
      out=""
      [[ "${1:-}" == "--out" ]] && { out="${2:?file}"; shift 2; }
      [[ "${1:-}" == "--as-of" ]] && { asof=$(_as_of_epoch "${2:?time}"); shift 2; }
      if [[ -n "$asof" ]]; then export WALKAWAY_DATA_NOW=$asof; fi
      if [[ -n "$out" ]]; then data_dump "$cfg" "$@" > "$out"; echo "wrote $out"; else data_dump "$cfg" "$@"; fi
      ;;
    floors) data_floors "$cfg" ;;
    tick)      data_tick ;;
    evaluate)  data_evaluate "$cfg" "${1:?series}" ;;
    status)    data_status ;;
    heartbeat) data_heartbeat_lines ;;
    state)     jq . "$(_dstate_file "${1:?series}")" ;;
    inventory-diff) data_inventory_diff "$cfg" "${1:?ids-file}" ;;
    *) echo "Usage: data.sh list | check <series> [--as-of T] | dump [--out F] [--as-of T] [series=T ...] | floors | inventory-diff <ids-file> | tick | evaluate <series> | status | heartbeat | state <series>" >&2; exit 1 ;;
  esac
fi

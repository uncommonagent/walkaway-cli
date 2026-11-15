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
#
# T = "YYYY-MM-DD HH:MM" (ET) or an epoch. Counts are READ-ONLY: one REST GET per period with Prefer: count=exact and
# Range: 0-0 (aggregates are disabled on both projects). The service-role key is read from the source's env file at
# call time and handed to curl on stdin (-K -), never in argv, logs or output.
#
# Test seams: WALKAWAY_DATA_FILE (series.yaml), WALKAWAY_DATA_NOW (epoch "now"), WALKAWAY_DATA_FIXTURES=<dir>
# (period counts of series <s> come from <dir>/<s>.json {"<period anchor>": count}; missing anchor = 0; a key
# "__error" = every count errors).

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
  for (( k = 0; k <= n; k++ )); do printf '%s\t%s\n' "$k" "$(_anchor_back "$cad" "$cur" "$k")"; done
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
  if [[ -n "${WALKAWAY_DATA_FIXTURES:-}" ]]; then
    fx="${WALKAWAY_DATA_FIXTURES}/${name}.json"
    if [[ -f "$fx" ]] && jq -e 'has("__error")' "$fx" > /dev/null 2>&1; then echo "E:$(jq -r .__error "$fx")"; return 0; fi
    [[ -f "$fx" ]] && jq -r --arg a "$a" '.[$a] // 0' "$fx" || echo 0
    return 0
  fi
  _rest_count "$cfg" "$(jq -r .source <<< "$s")" "$(_count_path "$s" "$a" "$4")"
}

# ── check ────────────────────────────────────────────────────────────────────

# data_check <config> <series> [only-anchors-json] -> JSON
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
    if (( ra <= now )) && { [[ -z "$only" ]] || jq -e --arg a "$a" 'index($a) != null' <<< "$only" > /dev/null; }; then
      ( _count "$cfg" "$s" "$a" "$ctx" > "$tmp/$i" ) &
    fi
    i=$((i + 1))
  done < <(_periods "$s")
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
    inventory-diff) data_inventory_diff "$cfg" "${1:?ids-file}" ;;
    *) echo "Usage: data.sh list | check <series> [--as-of T] | dump [--out F] [--as-of T] [series=T ...] | floors | inventory-diff <ids-file>" >&2; exit 1 ;;
  esac
fi

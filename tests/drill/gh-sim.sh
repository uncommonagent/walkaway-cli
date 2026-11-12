#!/usr/bin/env bash
# Minimal `gh` stand-in for drills: scratch repos have a local bare origin, not a GitHub remote.
# PR state lives in $GH_SIM_DIR/<repo-basename>/<branch>.json. Supported:
#   gh pr view <branch|number> [--json ...]     prints the PR JSON (exit 1 if none)
#   gh pr checks <number>                       prints one passing check
#   gh pr diff <number>                         git diff origin/main...branch
#   gh pr merge <number> --squash [--delete-branch]   squash-merges into main, pushes, marks MERGED
#   gh pr create-sim <branch>                   (stub builder) opens a PR with one green check
# Every call is appended to $GH_SIM_DIR/calls.log.

set -uo pipefail

GH_SIM_DIR="${GH_SIM_DIR:?GH_SIM_DIR must be set}"
mkdir -p "$GH_SIM_DIR"
echo "$(date '+%H:%M:%S') $(pwd) gh $*" >> "$GH_SIM_DIR/calls.log"

[[ "${1:-}" == "pr" ]] || { echo "gh-sim: only 'pr' is supported" >&2; exit 1; }
sub="${2:-}"; arg="${3:-}"
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "gh-sim: not in a git repo" >&2; exit 1; }
common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)/.." && pwd)
dir="$GH_SIM_DIR/$(basename "$common")"
mkdir -p "$dir"

_find() { # branch or number -> json file
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    grep -l "\"number\": *$1[,}]" "$dir"/*.json 2>/dev/null | head -1
  else
    local f="$dir/${1//\//__}.json"
    [[ -f "$f" ]] && echo "$f"
  fi
}

case "$sub" in
  view)
    f=$(_find "$arg"); [[ -n "$f" ]] || { echo "no pull requests found for branch \"$arg\"" >&2; exit 1; }
    cat "$f" ;;
  checks)
    f=$(_find "$arg"); [[ -n "$f" ]] || exit 1
    printf 'drill-ci\tpass\t3s\thttps://example.invalid/drill-ci\n' ;;
  diff)
    f=$(_find "$arg"); [[ -n "$f" ]] || exit 1
    git -C "$common" diff "origin/main...$(jq -r .headRefName "$f")" ;;
  create-sim)
    until mkdir "$GH_SIM_DIR/.number-lock" 2>/dev/null; do sleep 0.2; done
    n=$(( $(cat "$GH_SIM_DIR/next-number" 2>/dev/null || echo 100) + 1 )); echo "$n" > "$GH_SIM_DIR/next-number"
    rmdir "$GH_SIM_DIR/.number-lock"
    jq -n --argjson n "$n" --arg b "$arg" '{number:$n, state:"OPEN", headRefName:$b, url:("sim://pr/"+($n|tostring)),
      mergeStateStatus:"CLEAN", statusCheckRollup:[{__typename:"CheckRun", name:"drill-ci", status:"COMPLETED", conclusion:"SUCCESS"}]}' \
      > "$dir/${arg//\//__}.json"
    echo "sim://pr/$n" ;;
  merge)
    f=$(_find "$arg"); [[ -n "$f" ]] || { echo "gh-sim: PR $arg not found" >&2; exit 1; }
    b=$(jq -r .headRefName "$f")
    (
      set -e
      cd "$common"
      git fetch -q origin
      git checkout -q main
      git merge -q --ff-only origin/main
      git merge -q --squash "origin/$b"
      git commit -q -m "$b (#$arg) [squash, gh-sim]"
      git push -q origin main
      if [[ " $* " == *" --delete-branch "* ]]; then
        git branch -q -D "$b" 2>/dev/null || true
        git push -q origin --delete "$b"
      fi
    ) || { echo "gh-sim: merge failed" >&2; exit 1; }
    tmp="$f.tmp"; jq '.state = "MERGED"' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "✓ Squashed and merged pull request #$arg ($b)" ;;
  *) echo "gh-sim: unsupported pr $sub" >&2; exit 1 ;;
esac

#!/usr/bin/env bash
# Minimal `gh` stand-in for drills: scratch repos have a local bare origin, not a GitHub remote.
# PR state lives in $GH_SIM_DIR/<repo-basename>/<branch>.json. Supported:
#   gh pr view <branch|number> [--json ...]     prints the PR JSON (exit 1 if none)
#   gh pr checks <number>                       prints one passing check
#   gh pr diff <number>                         git diff origin/main...branch
#   gh pr merge <number> --squash [--delete-branch]   squash-merges into origin main (in a temp clone, like
#                                               GitHub's server side), marks MERGED; --delete-branch also
#                                               deletes the branch (and, like gh, moves a checkout on it to main)
#   gh pr create-sim <branch>                   (stub builder) opens a PR with one green check
# `pr view` reports headRefOid = the branch tip on origin (what GitHub shows after a push).
# Every call is appended to $GH_SIM_DIR/calls.log ("<HH:MM:SS> <epoch> <cwd> gh <args>"). Knobs (tests):
#   fail-view    `pr view` fails like a gh/API error       fail-merge    `pr merge` fails like a merge conflict
#   stale-head   `pr view` keeps reporting the head recorded at PR creation (GitHub lagging behind a push)
#   empty-checks `pr view` reports an empty statusCheckRollup (no checks registered yet / no CI)

set -uo pipefail

GH_SIM_DIR="${GH_SIM_DIR:?GH_SIM_DIR must be set}"
mkdir -p "$GH_SIM_DIR"
echo "$(date '+%H:%M:%S') $(date +%s) $(pwd) gh $*" >> "$GH_SIM_DIR/calls.log"

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
    [[ -f "$GH_SIM_DIR/fail-view" ]] && { echo "gh-sim: simulated API error" >&2; exit 1; }
    f=$(_find "$arg"); [[ -n "$f" ]] || { echo "no pull requests found for branch \"$arg\"" >&2; exit 1; }
    head=""
    if [[ ! -f "$GH_SIM_DIR/stale-head" ]]; then
      head=$(git -C "$common" ls-remote origin "refs/heads/$(jq -r .headRefName "$f")" 2>/dev/null | cut -f1)
    fi
    [[ -f "$GH_SIM_DIR/stale-head" ]] && echo "  view: stale head" >> "$GH_SIM_DIR/calls.log"
    [[ -f "$GH_SIM_DIR/empty-checks" ]] && echo "  view: empty rollup $(date +%s)" >> "$GH_SIM_DIR/calls.log"
    jq --arg h "$head" --argjson empty "$([[ -f "$GH_SIM_DIR/empty-checks" ]] && echo true || echo false)" \
      '(if $h != "" then .headRefOid = $h else . end) | (if $empty then .statusCheckRollup = [] else . end)' "$f" ;;
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
    jq -n --argjson n "$n" --arg b "$arg" --arg h "$(git rev-parse HEAD)" '{number:$n, state:"OPEN", headRefName:$b, headRefOid:$h, url:("sim://pr/"+($n|tostring)),
      mergeStateStatus:"CLEAN", statusCheckRollup:[{__typename:"CheckRun", name:"drill-ci", status:"COMPLETED", conclusion:"SUCCESS"}]}' \
      > "$dir/${arg//\//__}.json"
    echo "sim://pr/$n" ;;
  merge)
    [[ -f "$GH_SIM_DIR/fail-merge" ]] && { echo "gh-sim: simulated merge conflict" >&2; exit 1; }
    f=$(_find "$arg"); [[ -n "$f" ]] || { echo "gh-sim: PR $arg not found" >&2; exit 1; }
    echo "  worktrees at merge: $(git -C "$common" worktree list | wc -l | tr -d ' ')" >> "$GH_SIM_DIR/calls.log"
    b=$(jq -r .headRefName "$f")
    origin=$(git -C "$common" remote get-url origin)
    clone=$(mktemp -d)
    (
      set -e
      git clone -q --branch main "$origin" "$clone/m"
      cd "$clone/m"
      git -c user.email=gh-sim@example.invalid -c user.name=gh-sim merge -q --squash "origin/$b"
      git -c user.email=gh-sim@example.invalid -c user.name=gh-sim commit -q -m "$b (#$arg) [squash, gh-sim]"
      git push -q origin main
      if [[ " $* " == *" --delete-branch "* ]]; then git push -q origin --delete "$b"; fi
    ) || { rm -rf "$clone"; echo "gh-sim: merge failed" >&2; exit 1; }
    rm -rf "$clone"
    if [[ " $* " == *" --delete-branch "* ]]; then
      # gh: a local checkout on the merged branch moves to the default branch, then the local branch goes.
      if [[ "$(git -C "$common" symbolic-ref --quiet --short HEAD)" == "$b" ]]; then
        git -C "$common" checkout -q main && git -C "$common" pull -q --ff-only origin main
      fi
      git -C "$common" branch -q -D "$b" 2>/dev/null || true
    fi
    tmp="$f.tmp"; jq '.state = "MERGED"' "$f" > "$tmp" && mv "$tmp" "$f"
    echo "✓ Squashed and merged pull request #$arg ($b)" ;;
  *) echo "gh-sim: unsupported pr $sub" >&2; exit 1 ;;
esac

# Smoke Results: walkaway-cli

Date: 2026-05-24

## Test 1: Plan parser — BPO Phase 3 fixture

```
bash lib/parse-plan.sh ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md
```

Output:
```
FEATURE_NAME=bpo-j-phase-3
BRANCH_NAME=feature/bpo-j-phase-3
REPO_PATH=/Users/jimross/Projects/Throughline/throughline-app
```

Result: PASS. REPO_PATH correctly inferred from plan file location (two levels up).

## Test 2: Unit test suite

```
bash tests/test-parse-plan.sh
```

Output:
```
Fixture 1: BPO Phase 3 — 3/3 PASS
Fixture 2: walkaway-cli plan — 3/3 PASS
Fixture 3: missing file error — 1/1 PASS

Results: 7 passed, 0 failed
```

Result: PASS.

## Test 3: walkaway --help (via installed symlink)

```
walkaway --help
```

Result: PASS. All flags documented (--worktree, --dry-run, --force, --help).
Symlink resolution confirmed working.

## Test 4: walkaway --dry-run against BPO Phase 3

```
walkaway --dry-run ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md
```

Output summary:
- Feature: bpo-j-phase-3
- Branch:  feature/bpo-j-phase-3
- Repo:    /Users/jimross/Projects/Throughline/throughline-app
- Would start watcher → ~/.walkaway-cli/logs/watcher-bpo-j-phase-3.log
- Prompt preview: "You are executing a walkaway build per /Users/jimross/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md..."

Result: PASS. All values correct. Protocol path resolved to real file.

## Test 5: Watcher state file path

State would be written to:
```
~/.walkaway-cli/state/watcher-bpo-j-phase-3.json
```
Log to:
```
~/.walkaway-cli/logs/watcher-bpo-j-phase-3.log
```

Result: PASS. Feature-name suffixing confirmed in dry-run output.

## Notes

- shellcheck not installed on this machine (skipped per build plan note)
- No real CC launch executed during smoke (correct per plan: "Do NOT run a real walkaway build")
- Block 2 template renders correctly via sed substitution — no envsubst dependency

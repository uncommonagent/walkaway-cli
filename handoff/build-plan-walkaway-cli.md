# Build Plan: walkaway-cli

One command kicks off a walkaway build. Parses the build plan, creates the branch, launches CC with Block 2 pre-loaded as the initial prompt, starts the notification watcher, and handles parallel worktrees when needed.

Replaces the current two-block copy-paste ritual.

---

## Feature name

`walkaway-cli`

## Repo

New repo: `~/Projects/walkaway-cli/` (created). GitHub: `uncommonagent/walkaway-cli` (public OK or private — Jim's call).

## Branch name

`main` (single-branch, no feature branches for this build)

## Goal

A single command Jim runs from any terminal that takes a build plan path and kicks off a complete walkaway build session: branch creation, watcher startup, CC launch with Block 2 prompt loaded as positional argument, optional worktree creation for parallel sessions. Replaces the current copy-Block-1 / copy-Block-2 workflow.

After this ships, kicking off a walkaway build becomes:
```
walkaway ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-4.md
```

And for parallel:
```
walkaway --worktree ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-4-parallel.md
```

## Non-goals

- Build plan authoring (Jim still writes those with Claude in chat)
- Codex review automation (CC handles this in Phase 7 of every build)
- Build report parsing or summarization
- Status check ritual replacement (the existing "status" trigger still goes through Desktop Commander)
- Anything that touches Throughline, Showrunner, or any specific project's code
- A GUI or web interface — terminal CLI only
- Cross-platform support beyond macOS (Jim's only environment)
- Watcher infrastructure changes (use existing `scripts/watch-handoff.sh` in the BPO repo as-is)

## Acceptance criteria

- `walkaway <build-plan-path>` parses the plan and successfully kicks off a CC session in the correct repo with Block 2 loaded as the initial prompt
- The script extracts feature name, branch name, and repo path from the plan's metadata fields (Feature name, Branch name, Repo) automatically
- If branch already exists locally, the script asks before deleting+recreating (prevents accidental destroy of in-progress work)
- The notification watcher starts in the background BEFORE CC launches, logs to `~/.walkaway-cli/logs/watcher-<feature>.log`
- The watcher state file uses the feature name as suffix to prevent collision across parallel builds
- `--worktree` flag creates a git worktree at `../<repo-basename>-<feature>`, copies `.env.local` from the source repo, runs `pnpm install` (or detected package manager) in the worktree, opens it in a new VS Code window, then launches CC there
- `--dry-run` flag prints what the script WOULD do without executing anything (verification mode)
- If another walkaway is already running (detected by watcher PID files), the script refuses to start unless `--force` is passed
- Block 2 is built from a template that combines the standard wrapper text with the specific build plan path (Jim does not need to write Block 2 manually anymore)
- The CC command uses positional-argument prompt format (`claude --dangerously-skip-permissions "PROMPT"`) — verified working during plan research
- The script is installable via a one-time `./install.sh` that symlinks `walkaway` into `/usr/local/bin` or `~/.local/bin`
- Includes a `walkaway --help` that documents all flags
- The script is idempotent for safe re-runs (re-running after a failed kickoff cleans up partial state)
- Local production check: install via install.sh, run `walkaway --dry-run` against an existing real build plan from the Throughline repo, confirm the output makes sense

## Expected files touched

Soft budget. Hard ceiling: 10 files.

- `walkaway.sh` (main script, bash; could be Node if shell gets gnarly but try bash first)
- `lib/parse-plan.sh` (extracts metadata from build plan markdown)
- `lib/launch-cc.sh` (builds Block 2 prompt and executes claude command)
- `lib/worktree.sh` (handles git worktree creation, env copy, install)
- `lib/watcher.sh` (starts notification watcher with feature-tagged state)
- `templates/block-2-template.md` (the wrapper prompt with `${BUILD_PLAN_PATH}` placeholder)
- `install.sh` (symlinks to user PATH)
- `README.md` (usage, install, troubleshooting)
- `.gitignore` (logs, state files)
- `tests/test-parse-plan.sh` (basic smoke test for plan parsing against a fixture)

## Content brief

### What Block 2 template should contain

The template at `templates/block-2-template.md` should be a generalized version of every Block 2 prompt Jim has used to date. Variables substituted at runtime:

- `${BUILD_PLAN_PATH}` — absolute path to the build plan
- `${FEATURE_NAME}` — extracted from plan
- `${WALKAWAY_PROTOCOL_PATH}` — absolute path to WALKAWAY_BUILD_PROTOCOL.md (lives in BPO repo)
- `${REPO_PATH}` — absolute path to the target repo (extracted from plan)

The template body:

```
You are executing a walkaway build per ${WALKAWAY_PROTOCOL_PATH}.

Read these in order before touching code:
1. ${WALKAWAY_PROTOCOL_PATH} (operating rules)
2. ${BUILD_PLAN_PATH} (the plan — this is the contract)
3. CLAUDE.md, TOOLCHAIN_OVERVIEW.md, and any other top-level docs in ${REPO_PATH} for project conventions

Context: You are on branch <will be set by script>. Execute all phases from the build plan. Each phase ends with the mandatory gates per WALKAWAY_BUILD_PROTOCOL.md. Commit and push after each successful phase.

Phase 6 (smoke) is MANDATORY. Phase 7 (Codex review) is MANDATORY. Phase 8 (final report) is MANDATORY.

Stop rules from the plan apply. Do NOT build anything in the plan's "Do NOT build" section.

Write phase reports to handoff/phase-N-report-${FEATURE_NAME}.md after each phase. Append one-liners to handoff/build-log-${FEATURE_NAME}.md.

Print when done: every file modified per phase, all gate results, Codex findings + fixes, all smoke results with real evidence, PR URL, and anything deferred or flagged as follow-up.
```

The script substitutes the variables, then passes the resulting prompt as a single positional argument to `claude --dangerously-skip-permissions`.

## Phases

### Phase 1: Plan parser

Build `lib/parse-plan.sh`. Takes a build plan markdown file path, extracts:
- Feature name (matches `## Feature name\n\n` followed by a backticked value)
- Branch name (matches `## Branch name\n\n` followed by a backticked value)
- Repo path (matches `## Repo` section if present, otherwise inferred from the build plan's parent directory: the plan lives in `<repo>/handoff/build-plan-<feature>.md`, so `<repo>` is two levels up)

Output as KEY=VALUE pairs to stdout for downstream scripts to source.

Test fixture: use the actual `build-plan-bpo-j-phase-3.md` from the Throughline repo. Assert correct parsing.

### Phase 2: Watcher startup

Build `lib/watcher.sh`. Starts the existing `scripts/watch-handoff.sh` from the BPO repo in the background with a feature-tagged state file. PID and log path stored at `~/.walkaway-cli/state/watcher-<feature>.json`. Refuses to start if a watcher for that feature is already running (idempotent restart logic).

### Phase 3: CC launcher

Build `lib/launch-cc.sh`. Renders the Block 2 template with variable substitution, then executes:
```
cd "${REPO_PATH}" && claude --dangerously-skip-permissions "${RENDERED_PROMPT}"
```

The cd happens because CC needs to start in the repo root. The script does NOT background CC — it foregrounds so Jim sees the session and can interact if needed.

### Phase 4: Worktree handler

Build `lib/worktree.sh`. When `--worktree` flag is set:
1. `git worktree add ../<repo-basename>-<feature> -b <branch>`
2. `cp <source-repo>/.env.local <worktree>/.env.local` (if .env.local exists)
3. Detect package manager (pnpm/npm/yarn/bun) by inspecting lockfiles
4. Run `<pm> install` in the worktree
5. `open -a "Visual Studio Code" <worktree>` to open in a new VS Code window
6. Hand off to launch-cc.sh with the worktree as REPO_PATH

### Phase 5: Main script and install

Build `walkaway.sh` that orchestrates the above. Handles arg parsing (`--worktree`, `--dry-run`, `--force`, `--help`). Calls into lib scripts in order.

Build `install.sh` that symlinks `walkaway.sh` to `/usr/local/bin/walkaway` (or `~/.local/bin/walkaway` if user lacks sudo). Make script executable.

### Phase 6: Smoke test (MANDATORY)

- Run `walkaway --dry-run ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md` and verify the printed plan-of-action is correct
- Run `walkaway --help` and verify all flags documented
- Run plan parser standalone against the BPO Phase 3 fixture and verify extracted values
- Confirm watcher state file path resolves correctly
- Document in `handoff/smoke-results-walkaway-cli.md`

Do NOT run a real walkaway build during the smoke. The next real BPO build is where it gets validated under real conditions.

### Phase 7: Final report and handoff

- Write `handoff/build-report-walkaway-cli.md`
- Write `handoff/build-report-CURRENT.md` (identical)
- Document: install path, usage examples, the Block 2 template, known limitations
- No Codex review for this build (shell scripts, low complexity, low risk)
- No PR (single-branch main repo, ship directly)

Acceptance: README and build report exist with clear install + first-use instructions. Jim can run `walkaway` from any terminal after running install.sh.

## Do NOT build

- A GUI or TUI
- Build plan validation beyond the basic metadata parse (don't enforce schema, don't lint the plan)
- Codex review wiring (CC handles that inside the build)
- Notification system replacement (use existing ntfy.sh + watch-handoff.sh)
- A "kill running walkaway" command (Jim can ctrl-c CC and kill the watcher manually)
- A plan templating system (Jim writes plans with Claude in chat, not via CLI)
- Anything that modifies the build plan during execution
- Multi-repo coordination (one repo per walkaway invocation; parallel = separate invocations)
- Status check replacement (existing "status" trigger via Desktop Commander stays)
- Build report parsing or rollup
- Any dependency on Node, Python, or any runtime beyond bash + git + the claude CLI

## Stop rules (build-specific)

Stop immediately if:
- The `claude --dangerously-skip-permissions "PROMPT"` positional-argument pattern fails in testing (Block 2 doesn't load correctly). Means stdin-piping is required instead, which changes the architecture.
- Plan parser can't reliably extract metadata from the BPO Phase 3 build plan (the real-world reference). Means plan format is too inconsistent and needs standardization first.
- Watcher startup conflicts with existing running watchers without the feature-tagged state. Means state file design needs rework.
- `git worktree add` fails on the test repo for any reason beyond "already exists." Means worktree handling needs more care.

## Required env vars

None.

## Required test data

- The existing `~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md` as the parser fixture (real-world example)
- The existing `~/Projects/BPO/bpo-comp-tool/scripts/watch-handoff.sh` as the watcher reference
- The existing `~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md` as the protocol path target

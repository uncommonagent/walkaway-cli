# walkaway-cli

One command kicks off a walkaway build: branch setup, watcher start, CC launch with Block 2 pre-loaded. Replaces the copy-Block-1 / copy-Block-2 ritual.

## Install

```bash
cd ~/Projects/walkaway-cli
./install.sh
```

The installer symlinks `walkaway` into `/usr/local/bin` (or `~/.local/bin` if you lack write access). Re-running is safe.

## Usage

### Solo build

```bash
walkaway ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-4.md
```

This:
1. Parses the plan for `FEATURE_NAME`, `BRANCH_NAME`, `REPO_PATH`
2. Creates (or switches to) the branch in the target repo
3. Starts the ntfy.sh watcher in the background
4. Launches CC in the repo with Block 2 pre-loaded as the initial prompt

CC runs in the foreground so you can watch and interact.

### Parallel build (worktree)

```bash
walkaway --worktree ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-k.md
```

Creates a git worktree at `../<repo>-<feature>`, copies `.env.local`, runs `pnpm install`, opens VS Code, then launches CC there.

### Dry run (verify without executing)

```bash
walkaway --dry-run ~/Projects/Throughline/throughline-app/handoff/build-plan-bpo-j-phase-3.md
```

Prints what would happen — plan parse results, branch name, watcher path, and a prompt preview — without touching anything.

## Flags

| Flag | Description |
|---|---|
| `--worktree` | Create a git worktree for a parallel build |
| `--dry-run` | Print plan-of-action without executing |
| `--force` | Skip the "already running" collision guard |
| `--help` | Show usage |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `WALKAWAY_PROTOCOL_PATH` | `~/Projects/BPO/bpo-comp-tool/handoff/WALKAWAY_BUILD_PROTOCOL.md` | Override protocol path |
| `NTFY_TOPIC` | `jim-throughline-9k2x7q-builds` | ntfy.sh topic |

## Block 2 template

The prompt sent to CC lives at:

```
~/Projects/walkaway-cli/templates/block-2-template.md
```

Edit this file to adjust the wrapper text. Variables substituted at runtime:

- `${BUILD_PLAN_PATH}` — absolute path to the build plan
- `${FEATURE_NAME}` — extracted from plan
- `${BRANCH_NAME}` — extracted from plan
- `${WALKAWAY_PROTOCOL_PATH}` — absolute path to WALKAWAY_BUILD_PROTOCOL.md
- `${REPO_PATH}` — absolute path to the target repo

## State and logs

```
~/.walkaway-cli/state/watcher-<feature>.json   Watcher PID + metadata
~/.walkaway-cli/logs/watcher-<feature>.log     Watcher output
~/.walkaway-cli/state/.watcher-state-<feature> Handoff dir file snapshot
```

## Plan format requirements

Build plans must have these sections:

```markdown
## Feature name

`my-feature`

## Branch name

`feature/my-feature`
```

Repo path is inferred from the plan file's location (`<plan-file>/../../` = repo root) unless a `## Repo` section is present with a backtick-quoted path.

## Troubleshooting

**"Another walkaway is already running"** — use `--force` or kill the existing watcher:
```bash
cat ~/.walkaway-cli/state/watcher-<feature>.json  # get PID
kill <pid>
rm ~/.walkaway-cli/state/watcher-<feature>.json
```

**Template variable not substituting** — check that your plan has both `## Feature name` and `## Branch name` sections with backtick-quoted values on the following line.

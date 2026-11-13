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

### Status

```bash
walkaway status
```

One table from the build registry: feature, repo, state, age, time in state, last action, plus the supervisor's last tick. Use this for status checks instead of `ps | grep`.

## Supervisor (launchd, every 2 min)

```bash
./install-supervisor.sh              # install + load com.jimross.walkaway-supervisor, adopt running builds
./install-supervisor.sh --uninstall  # unload + remove
```

Every `walkaway` launch writes `~/.walkaway-cli/registry/<feature>.json` (builder PID = the walkaway process that execs the builder, watcher PID from the launch; never name-matched). The supervisor (`lib/supervisor.sh tick`) classifies each registered build as RUNNING, STALLED (alive, 40 min idle), STOPPED (failure report newer than last launch), DIED (PID gone, no new report), DONE (build report + PR open + checks green), MERGED or ESCALATED, and sends one ntfy line `<feature>: <STATE> - <action>` on every change (plus a 09/13/17 ET heartbeat while anything is RUNNING/ESCALATED). While it is installed, watchers no longer ping on their own.

The operator (`lib/operator.sh`, judgment by headless `claude -p` with `templates/operator-prompt.md`) acts on it:

| State | Action |
|---|---|
| DIED / STALLED | kill leftovers, auto RESUME DIRECTIVE in the plan, relaunch (cap 2, then ESCALATE) |
| STOPPED | triage: approve in-scope, non-PROTECTED fix as a RESUME DIRECTIVE + relaunch, else ESCALATE one question |
| DONE | merge gate: verify evidence vs acceptance criteria; PASS (all criteria met, CI green, Codex closed; CI re-verified on the open PR after the gate push) = squash-merge + launch next queued plan, FAIL = rejection directive + relaunch (cap 2) |

A worktree build's worktree and branch are removed only after the merge succeeds; a failed merge escalates and leaves the worktree intact. Only `failure-report-<feature>.md` and `failure-report-<feature>-{phase,codex,context}*.md` count as a build's stop.

Decisions are appended to `handoff/operator-log-<feature>.md` in the build repo and committed. The final MERGED outcome goes to `~/.walkaway-cli/logs/operator-<feature>.log`, the registry and ntfy (never an uncommitted write into the repo). PROTECTED actions (spend, credentials, Audrey's live lists / customer sends, deletion beyond named throwaways, unqueued launches, "Jim decides", any uncertainty) always ESCALATE.

Queue: `~/.walkaway-cli/queue/<repo-basename>.txt`, one absolute plan path per line. After a merge the next plan for that repo launches (one builder per repo; repos run in parallel).

Classification order (11/13 fix): a build report **committed at the branch head** since the last non-resume launch is DONE first (green CI starts the gate; pending CI waits; a plan that says "no PR yet" is DONE; no PR and the builder gone = STOPPED). DIED needs all three: builder PID gone, no build report at the branch head, and no activity for 3 min (`WALKAWAY_DIED_GRACE_SECS`). An auto-resume keeps the report baseline, and a resumed builder that finds nothing to do appends "(no-op resume)" to the build report and exits.

## Scheduled-job watching (jobs.yaml)

```bash
./install-supervisor.sh --jobs-on    # touch ~/.walkaway-cli/jobs.enabled (--jobs-off removes it)
bash lib/jobs.sh list                # the jobs
bash lib/jobs.sh check bf-daily      # one read-only check (JSON); --date YYYY-MM-DD for a past day
bash lib/jobs.sh dump                # every job's check with its queries, row counts and sample rows
```

`jobs.yaml` lists Jim's scheduled daily jobs (BF daily, CC opt-in AM/PM, SPC, extension reports, ShowingTime, Monday RealTea generate/publish) with the owner repo, schedule window, retry-window end, read-only check (Supabase REST GETs with the service-role key read from the owner repo's `.env.local` at call time and passed to curl on stdin, plus log greps) and a jq predicate. While job watching is on, every supervisor tick moves each job through one state per day:

| State | Meaning | ntfy |
|---|---|---|
| PENDING | window not open / not run / in progress | - |
| RETRYING | failed inside its own retry window | - (no alert) |
| OK | done today | only when it resolves a failure ("resolved") |
| FAILED | retry window passed (or terminal: HALTED, STOP:, no success in 26 h) | one line, then the job operator |
| FIXING | fix build queued/launched | one line |
| ESCALATED | one question for Jim | one line, priority high |

The job operator (`lib/job-operator.sh`, headless `claude -p` with `templates/job-operator-prompt.md`, read-only tools) diagnoses from the rows, logs and owner-repo code, writes `handoff/job-incident-<job>-<date>.md` in `~/.walkaway-cli/job-fixes/<job>-<date>/`, and then either renders a template-v2 fix plan (`## Repo` = owner repo) that is queued/launched like any walkaway build (one per job per day, one builder per repo), or escalates ONE question when the cause or fix touches a PROTECTED action, needs the job's live action on a protected job, or is not high-confidence. After the fix merges it runs the job's safe retry path once (`retry.command`; only ShowingTime has one) and the next check confirms OK. The 09/13/17 heartbeat lists every non-OK job whose window has opened; `walkaway status` prints a JOBS table under the builds.

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
| `WALKAWAY_HOME` | `~/.walkaway-cli` | Registry/queue/state/log root (drills use a scratch one) |
| `WALKAWAY_BUILDER_CMD` | `claude` | Builder binary (drills use a stub) |

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
~/.walkaway-cli/registry/<feature>.json        Build registry (supervisor state)
~/.walkaway-cli/queue/<repo>.txt               Plans launched after each merge
~/.walkaway-cli/logs/supervisor.log            Supervisor ticks
~/.walkaway-cli/logs/operator-<feature>.log    Operator jobs
~/.walkaway-cli/logs/ntfy.log                  Every ntfy line sent
~/.walkaway-cli/jobs.enabled                   Job watching on (flag file)
~/.walkaway-cli/jobs/state/<job>.json          Job day state (state, last OK, last action, fix build)
~/.walkaway-cli/job-fixes/<job>-<date>/handoff Incident, evidence JSON, generated fix plan
~/.walkaway-cli/logs/job-operator-<job>.log    Job operator runs
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

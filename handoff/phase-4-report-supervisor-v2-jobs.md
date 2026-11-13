# Phase 4 report - supervisor-v2-jobs (job operator, plan item 4)

- **`lib/job-operator.sh diagnose <job> <date>`** (spawned detached by the job watch on FAILED):
  1. Gathers the evidence read-only with the same check engine: the failing check rows, the job's `diagnose` queries and log greps, its jobs.yaml entry and its day state. Saved as evidence-<job>-<date>.json.
  2. Asks headless `claude -p` for a diagnosis, using `templates/job-operator-prompt.md` and a JSON schema.
     - Tools are Read/Glob/Grep plus git log/show/diff, run in the owner repo.
     - curl, open, Edit/Write, commit, push and rm are disallowed; no keys are passed.
  3. Writes `handoff/job-incident-<job>-<date>.md` (cause, evidence, decision, check + diagnose rows) in the fix workspace `$WALKAWAY_HOME/job-fixes/<job>-<date>/handoff/`.
- **Deterministic guards (escalate):**
  - no decision
  - protected_hit
  - a protected job whose fix needs its live action
  - confidence below high
  - a fix with no what_to_build
  - a second auto-fix for the job on the same day

  Escalation = ESCALATED with ONE question (the model's question, or a generated one-liner), ntfy priority high.
- **Fix path:**
  - Renders a **template-v2 plan** from the structured fields: every v2 section, `## Repo` = owner repo, cites the job's quality-rules file (bf-daily → showrunner-lists.md), adds a mandatory regression-fixture AC from the incident rows, a gates AC, and a stop rule "never trigger the job's live action".
  - Appends the plan to `queue/<repo>.txt`, then launches it via walkaway if no other build is active in that repo; otherwise it stays queued and the existing post-merge `_launch_next` starts it.
  - The job moves to FIXING, with one ntfy naming the cause and "launched (pid)" or "queued behind X".
  - A launch failure ESCALATES.
  - An earlier fix still in flight goes to FIXING with no new build.
- **Deviation (logged):**
  - The plan says "writes a fix plan in the owner repo". The plan lives in the fix workspace with `## Repo` → owner repo, and its Phase 0 commits the plan, incident and evidence into the owner repo's handoff/ on the fix branch.
  - Reason: writing untracked files into an owner repo's root checkout could land inside another builder's PR (audrey-ops-platform currently has bf-taste-scoring running there). It would also trip walkaway's base guard if the plan had to be committed to main first.
- **`job-operator.sh progress`** (each tick while FIXING) follows the fix build's registry state. On MERGED it runs the job's `retry.command` exactly once (only if the job is not protected; 60 s bound, output in logs/job-retry-<job>.log). The job watch's next read-only check confirms OK and sends the single "resolved" ntfy. Jobs without a safe retry path wait for their next scheduled run.
- **Job watch:** a FAILED job whose operator exited without recording a decision now ESCALATES ("Job operator exited without a decision"). Failures are never left silent.
- **`tests/test-job-operator.sh` (new): 25/25**, run with scratch owner repos, the real walkaway launch, the stub builder, stub claude and the real predicates on real rows:
  - incident + v2 plan + launch
  - one fix per day
  - protected → one question, no plan/queue/build
  - medium confidence escalates
  - busy repo → queued
  - MERGED → retry exactly once → OK → one resolved ntfy
  - no-retry job waits
  - one ntfy per transition
- **`tests/test-jobs-states.sh`: 36/36.** Its stub operator now moves FAILED to FIXING like a real fix decision, and a silent-operator scenario was added.
- **Gates:** shellcheck -S warning 0 (combined + per-file); parse 7/7, states 18/18, regression 12/12, jobs-states 36/36, job-operator 25/25, operator 68/68. Job watching is still OFF live (no jobs.enabled).
- **Files:** lib/job-operator.sh (new), templates/job-operator-prompt.md (new), lib/jobs.sh, tests/test-job-operator.sh (new), tests/test-jobs-states.sh.

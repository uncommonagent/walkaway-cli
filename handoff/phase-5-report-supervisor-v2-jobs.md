# Phase 5 report - supervisor-v2-jobs (tests + drill harness + docs)

- **Full suite (6 files, 166 checks):**

  | Suite | Result |
  |---|---|
  | parse | 7/7 |
  | states | 18/18 |
  | AC1 regression | 12/12 |
  | jobs-states | 36/36 |
  | job-operator | 25/25 |
  | operator | 68/68 |

  shellcheck -S warning is 0 combined and 0 per-file.
- **Regression fixtures** come from real failures, captured read-only:
  - BF 11/13 06:30-07:43 failed rows, plus the recovered day, plus the run summaries ("listDealsExports call not seen in 15 s")
  - CC AM 11/04 HALTED
  - extension_report_state 11/13 (with a tracking_offsite error variant)
  - the 11/13 bf-deals-ingest-fix DIED timeline (AC1, which fails on the pre-fix lib)
- **`tests/drill/run-jobs-drill.sh` (new, AC3 live drill)** runs real supervisor ticks with job watching on, time travel, REAL `claude -p` diagnoses and REAL ntfy on a drill topic captured via the JSON poll. It checks the poll against the local send log 1:1.
  - Owner repos are throwaway shared clones whose origin is repointed at scratch bare repos: audrey at 7da72ae (before the 11/13 Deals Hub fix) and throughline at origin/main.
  - A registered busy build holds the audrey slot, so the fix plan is queued and never launched.
  - Scenarios: RETRYING silent, recovered silent, bf FAILED → incident + v2 plan queued, showingtime OTP (PROTECTED) → ESCALATED one question, resolution → one ntfy.
  - It runs in Phase 6.
- **`install-supervisor.sh`** gains `--jobs-on` / `--jobs-off` (the flag file the running supervisor reads; no reinstall needed). Uninstall also removes the flag.
- **README** documents:
  - the new classification order (DONE first, the DIED grace, no-op resume)
  - job watching: jobs.yaml, the commands, the state/ntfy table, the job operator, heartbeat, the JOBS status table, and the new state/log paths
- `.gitignore` adds tests/drill/work-jobs/.
- **Files:** tests/drill/run-jobs-drill.sh (new), tests/fixtures/jobs/bf-1113-runs-full.json (new), install-supervisor.sh, README.md, .gitignore.

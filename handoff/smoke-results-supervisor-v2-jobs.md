# Smoke results - supervisor-v2-jobs (Phase 6, real systems, 2026-11-13)

## AC2: every job's check against real rows (live Supabase, read-only GETs)
Evidence: handoff/supervisor-v2-jobs-evidence/ac2-jobs-check-dump.md. It records each query, row count, sample rows and verdict, and contains no keys (grep eyJ / sb_secret / service_role = 0).

| job | day | verdict | real rows |
|---|---|---|---|
| bf-daily | 2026-11-13 | OK | 6 bf_runs: 5 failed 11:30-13:50Z, then ok=true 14:21:05Z "deals 15000 (31435 live) from dealshub, drafts 1/1" |
| cc-optin-am | 2026-11-13 | OK | cc_optin_runs am DONE 16:25:19Z (export_rows 12384) |
| cc-optin-pm (disabled) | 2026-10-31 | OK | cc_optin_runs pm DONE 23:00:08Z (last PM row; PM off since 10/31) |
| spc | 2026-11-13 | OK | cc_spc_optins ACCEPTED 162/162 at 16:29:20Z |
| extension-reports | 2026-11-13 | OK | 13 extension_report_state rows; 10 watched types all succeeded within 26 h, none in error |
| showingtime | 2026-11-13 | OK | pulse_showings_daily 2026-11-12 total 2390 (first seen 11:45:43Z); st_session_attempts login_ok 174 rows; agent log `07:05:04 decision=SILENT_PRESENT` |
| realtea-generate | 2026-11-09 | OK | pulse_newsletter_issues #71 week_end 2026-11-08 generatedAt 13:31:35Z; monday_run_reports 3 rows complete |
| realtea-publish | 2026-11-09 | OK | #71 substackUrl https://uncommonagent.substack.com/p/realtea-roundup-71 |

## AC3: drill on fixtures, real claude, real ntfy (topic jim-walkaway-jobs-drill-addf5fe6)
Evidence: handoff/supervisor-v2-jobs-evidence/ac3-drill/. The drill passed 26/26 (drill-transcript.txt). The ntfy JSON poll returned 9 messages and the local send log has 9, a 1:1 match (ntfy-poll.json, ntfy-poll-messages.tsv, ntfy-local.log).

| Scenario | Result | ntfy |
|---|---|---|
| RETRYING: bf-daily (3 real failed 11/13 rows at 07:45), drill-export, extension tracking_offsite error | RETRYING; extension then recovered on its own retry at 08:20 → OK | none for any of them |
| FAILED → incident + fix plan queued: drill-export (throwaway job, scratch repo with a real code bug) FAILED at 09:01 | Real `claude -p` diagnosed in 35 s, confidence high: `r.ammount` typo at scripts/nightly-export.js:12 vs CSV header `amount`, expected total 49.75. Incident file and template-v2 plan (build-plan-fix-drill-export-20261113.md) written; plan queued behind drill-busy (queue file), not launched | one FAILED, one FIXING |
| FAILED with a protected cause → ESCALATED, one question: showingtime (OTP timeout fixture) FAILED at 12:46 | Claude escalated | one FAILED; one ESCALATED at priority 4 (high): "ShowingTime's 2FA code never reached the OTP endpoint on 11/13. Can you log in by hand and check that the code email still reaches Gmail? (yes / no, the 2FA phone or email changed)" |
| Real BF 11/13 rows, audrey clone at 7da72ae (before the fix) | Claude found that this morning's bf-deals-ingest-fix plan already covers the failure, and that verifying it needs a live Deals Hub probe plus a live draft in Audrey's account (protected) | one ESCALATED (high): "...run that plan, or no build today?" |
| Resolution: drill-export fix "merged" (registry MERGED) | Retry path ran exactly once (retry.log, 1 line); rows OK → OK | one "resolved" line |
| Resolution: bf recovered row | OK | one "resolved" line |

Polled transitions: drill-export [FAILED FIXING OK], bf-daily [FAILED ESCALATED OK], showingtime [FAILED ESCALATED], extension-reports [] (no transition repeated back-to-back).

## AC4: live on the Mini
Evidence: handoff/supervisor-v2-jobs-evidence/ac4-live/.

- `./install-supervisor.sh --jobs-on` at 12:13:47 ET. The launchd agent com.jimross.walkaway-supervisor is active (run interval 120 s, last exit code 0).
- The first live tick at 12:14:13-14 moved bf-daily, cc-optin-am, spc, extension-reports and showingtime from PENDING → OK on real rows (supervisor-log-job-lines.txt). The realtea jobs are off today (Fri) and the PM session is disabled.
- 0 job ntfy since job watching went on (ntfy-since-jobs-on.log is empty): nothing failed, and success is silent.
- `walkaway status` with the JOBS table: walkaway-status-live.txt (12:16) and walkaway-status-live-final.txt (refreshed after Phase 6).

## AC1 (re-run): 11/13 bf-deals-ingest-fix replay
handoff/supervisor-v2-jobs-evidence/ac1-regression-replay.txt:

- Fixed code: 12/12. DONE at the 09:28:47-equivalent tick, 0 resumes, 0 DIED.
- Pre-fix lib 830b728: 1/12, which reproduces DIED → resume → ESCALATED.

## AC5
handoff/supervisor-v2-jobs-evidence/ac5-gates.txt:

- shellcheck -S warning 0.
- 167/167 checks: parse 7, states 18, AC1 12, jobs-states 36, job-operator 26, operator 68.

## Bugs found by the smoke and fixed (regression-pinned)
- **Drill design:** the showingtime fixture was OK from the first tick, so it never re-checked. The drill now starts it missing.
- **Incident flags:** the incident printed `protected_hit: -` for false (jq `//` treats false as missing). Fixed in `_write_incident`, pinned by test-job-operator "incident records false flags as false".
- **FIXING ntfy:** it cut the cause at 120 chars mid-sentence. It now uses the cause's first sentence (160 max).

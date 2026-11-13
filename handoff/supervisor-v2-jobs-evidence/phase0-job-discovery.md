# Phase 0 job discovery - supervisor-v2-jobs (2026-11-13, read-only)

Every job was confirmed from the owner repo's code and from live Supabase rows. Each probe was a REST GET with the
service-role key read from the repo's `.env.local` and never printed. The anon key returns `[]` on every one of
these tables because RLS is service-only or scoped to the user/team. No writes were made and no job was triggered.

The plan's router doc (`~/Projects/ops/handoff/combined-thread-context-2026-10-26.md`) predates BF and SPC. It gives
no times or retry windows: L25 lists launchd agents, L35 Showrunner/CC opt-in, L44 the extension retry alarm. The
times below therefore come from the owner repos.

## Scheduler facts
- Showrunner jobs (BF daily, CC opt-in, SPC, extension reports) all run inside the Showrunner Chrome extension on
  the Mini. A 1-minute `poll-server` alarm drives them (`audrey-ops-platform/extension/config.js:3,7`,
  `extension/background.js:340-353`). None of them uses launchd, cron or Vercel cron.
- ShowingTime:
  - The pull runs in the Throughline ST extension: a random minute 06:00-06:45, a 07:00 login retry, and
    failed-date retries at 09:30 and 12:30 (`throughline-app/tools/showings-daily-pull/pull-core.js:307-317,420-421`).
  - launchd `com.jimross.st-login-agent` runs daily at 07:05 and logs `decision=...` lines to `/tmp/st-login-agent.log`.
- RealTea:
  - Generation is the Inngest `throughline/monday-autorun`, cron Monday 05:30 ET. Its data gate polls until 09:00
    (`throughline-app/inngest/functions/monday-autorun.ts:56-61`, `lib/newsletter/monday-autorun.ts:24,37`).
  - Publishing is launchd `com.throughline.substack-publisher`, Monday 07:00, polling until 10:00
    (`tools/substack-publisher/src/plan.ts:51-95`). The publisher writes `content.substackUrl` back.

## Jobs confirmed (plan item 2), with deviations from the plan's times
| job | owner repo | table / check | plan said | confirmed | why |
|---|---|---|---|---|---|
| bf-daily | audrey-ops-platform | bf_runs kind=daily, started today ET, any ok=true | ok by 12:00 | OK by 12:00 (retry every 30 min from 06:30, none after noon; `extension/bf-lists-lib.js:1123-1150`) | matches |
| cc-optin-am | audrey-ops-platform | cc_optin_runs session=am run_date=today status=DONE | DONE by 12:00 | **DONE by 15:45** | 11/05 AM DONE at 13:26 ET (updated_at 18:26Z), which would be a false FAILED at 12:00. The AM session rolls at 15:30 (`extension/cc-optin-lib.js:20-24`). HALTED is terminal, so it goes FAILED immediately |
| cc-optin-pm | audrey-ops-platform | cc_optin_runs session=pm | DONE by 19:30 | **disabled** (`enabled: false`) | PM session OFF since 10/31 (Jim): `pmSessionEnabled = false` at `extension/cc-optin-lib.js:26-29`. Last PM row is 2026-10-31. Watching it would FAIL every day. Check proven on the 10/31 row |
| spc | audrey-ops-platform | cc_spc_optins run_date=today status in (ACCEPTED, NOTHING_NEW) | run_date today by 17:30 | by 17:30 | matches. The extension retries/backoffs inside the day (`extension/cc-optin-spc-lib.js:29-36`) |
| extension-reports | audrey-ops-platform | extension_report_state: each daily type success within 26 h; error state persisting > 2 h | same | same. Error state = `last_error_at > last_success_at` or the `(prev: error)` dispatch marker (`src/lib/monitoring/extension-errors.ts:23-30`) | plain `dispatch pending - awaiting terminal result` is in flight, not an error |
| showingtime | throughline-app | pulse_showings_daily is_total obs_date=yesterday + st-login-agent decision | yesterday row by 07:30, decision not ACT_* | **expected 07:30, FAILED after 12:45** | The extension's own failed-date retries run 09:30 and 12:30. FAILED at 07:30 would contradict the goal ("once its own retry window has passed"). An ACT_* decision with the row still missing = RETRYING. The ACT_* decision is recorded in the job detail |
| realtea-generate | throughline-app | pulse_newsletter_issues week_end=last Sunday, content.substack.generatedAt set (Mon only) | by 08:30 Mon | **by 09:15 Mon** | 11/09 issue 71 generated 13:31Z = 08:31 ET, which would be a false FAILED at 08:30. The data gate cap is 09:00 |
| realtea-publish | throughline-app | same row, content->>substackUrl non-empty (Mon only) | by 10:00 Mon | **by 10:15 Mon** | the publisher polls until 10:00, and a publish started at 09:5x lands a few minutes later. 11/09 published 14:28Z = 09:28 ET |

## Real rows seen (excerpts, 2026-11-13 ~11:30 ET)
- bf_runs daily 11/13: 5 failures, then OK:
  - 11:30:35Z, 12:06:37Z, 12:43:36Z, 13:20:08Z: ok=false ("deals 39/45 from node | drafts 0/1").
  - 13:50:28Z: ok=false ("errors: Failed to fetch").
  - 14:21:05Z: ok=true ("deals 15000 (31435 live) from dealshub | drafts 1/1").
- cc_optin_runs am: 11/13 DONE (updated 16:25:19Z); 11/04 and 10/31 HALTED "unrecognized submit response (batch 0)".
  Last pm: 10/31 DONE.
- cc_spc_optins: 11/12 ACCEPTED 165/165 (15:27:57Z); 11/05 NOTHING_NEW. No 11/13 row yet at probe time (the AM
  ended 11:25 ET, so SPC runs after).
- extension_report_state: 13 types. tracking_offsite last_success 13:20:06Z and tracking_onsite 13:36:06Z;
  last_error_at null on all.
- pulse_showings_daily: obs_date 2026-11-12 total showings=2390, first_seen 11:45:43Z.
- st_session_attempts 11/13: login_ok / alarm 11:45:34Z rows=174. Smoke rows dated 2000-01-0x exist, so the date
  filter must be exact.
- /tmp/st-login-agent.log 11/13: `07:05:04 decision=SILENT_PRESENT yesterday=2026-11-12 present=1`. 11/12 holds smoke
  lines with `yesterday=1999-12-31`, so match on today's date AND the real yesterday.
- pulse_newsletter_issues (team d14dce4f-...): #71 week_end 2026-11-08, generatedAt 13:31:35Z, substackUrl
  .../realtea-roundup-71. monday_run_reports 11/09 complete, substackPublish at 14:28:12Z.

## Retry paths (plan item 4, "if the job has one")
- showingtime: `open -g -a "Google Chrome" "https://throughlinepro.com/#tl-ext-run-daily"`. This is the URL
  trigger the agent itself uses (`tools/login-agent/st-login-agent.sh:26,117`). It reads from ShowingTime into our
  table, and nothing is customer-facing.
- bf-daily: **no run-now path exists**. The popup has none and there is no API
  (`extension/background.js:259,265`). The extension retries every 30 min until noon by itself. The plan's
  "e.g. BF daily run-now" is not available: after a fix merges, the job is confirmed by the extension's next attempt
  or by the next day's run.
- cc-optin-am/pm, spc: the popup "run now" is a live action on Audrey's Amazon account (PROTECTED), so it is never
  auto-triggered.
- extension-reports: run-now needs a logged-in browser session (`run-now/route.ts`), so there is no scriptable path.
  The extension re-sends every 30 min inside its window.
- realtea-*: a re-fire sends an Inngest event (generation), and the publisher rerun publishes (PROTECTED).
  Neither is auto-triggered.

# jobs.yaml check dump - 2026-11-13 12:13 EST (read-only REST GETs; keys never printed)

## bf-daily (day 2026-11-13) -> OK
detail: 2026-11-13T14:21:05Z BF lists daily 11/13: OK | deals 15000 (31435 live) from dealshub | drafts 1/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok
query runs: bf_runs?select=started_at,finished_at,ok,line,error:summary->>error&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&kind=eq.daily&started_at=gte.2026-11-13T05:00:00Z&started_at=lt.2026-11-14T05:00:00Z&order=started_at.desc
rows runs: 6
sample runs: [{"started_at":"2026-11-13T14:21:05.991+00:00","finished_at":"2026-11-13T14:22:59.924+00:00","ok":true,"line":"BF lists daily 11/13: OK | deals 15000 (31435 live) from dealshub | drafts 1/1 | curations early_bf 0 ops ok, gift_guides 0 ops ok","error":null},{"started_at":"2026-11-13T13:50:28.213+00:00","finished_at":"2026-11-13T13:50:48.004+00:00","ok":false,"line":"BF lists daily 11/13: FAILED | errors: Failed to fetch","error":"Failed to fetch"},{"started_at":"2026-11-13T13:20:08.911+00:00","finished_at":"2026-11-13T13:27:54.662+00:00","ok":false,"line":"BF lists daily 11/13: FAILED | deals 3

## cc-optin-am (day 2026-11-13) -> OK
detail: DONE 2026-11-13T16:25:19Z
query run: cc_optin_runs?select=run_date,session,status,halted_reason,export_rows,updated_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&session=eq.am&run_date=eq.2026-11-13
rows run: 1
sample run: [{"run_date":"2026-11-13","session":"am","status":"DONE","halted_reason":null,"export_rows":12384,"updated_at":"2026-11-13T16:25:19.91+00:00"}]

## cc-optin-pm (day 2026-10-31) -> OK
detail: DONE 2026-10-31T23:00:08Z (rolled 2 batch(es) to the next session)
query run: cc_optin_runs?select=run_date,session,status,halted_reason,export_rows,updated_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&session=eq.pm&run_date=eq.2026-10-31
rows run: 1
sample run: [{"run_date":"2026-10-31","session":"pm","status":"DONE","halted_reason":"rolled 2 batch(es) to the next session","export_rows":10760,"updated_at":"2026-10-31T23:00:08.337+00:00"}]

## spc (day 2026-11-13) -> OK
detail: ACCEPTED 162/162 at 2026-11-13T16:29:20Z
query run: cc_spc_optins?select=run_date,status,listed,accepted,failed,remaining,detail,updated_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&run_date=eq.2026-11-13
rows run: 1
sample run: [{"run_date":"2026-11-13","status":"ACCEPTED","listed":162,"accepted":162,"failed":0,"remaining":0,"detail":null,"updated_at":"2026-11-13T16:29:20.95+00:00"}]

## extension-reports (day 2026-11-13) -> OK
detail: 10 report types succeeded within 26 h, none in error
query state: extension_report_state?select=report_type,last_success_at,last_error_at,last_error_message,updated_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748
rows state: 13
sample state: [{"report_type":"bounty","last_success_at":"2026-11-13T12:12:52.66+00:00","last_error_at":null,"last_error_message":"bounty parsed=0 errors=0 inserted=0 bytes=37 head=Name,Quantity,Ad Fees($) | -,12.0,88.0 | ","updated_at":"2026-11-13T12:12:52.728506+00:00"},{"report_type":"cc","last_success_at":"2026-11-13T12:15:31.128+00:00","last_error_at":null,"last_error_message":"cc parsed=9 errors=0 inserted=9 bytes=1527 head=﻿Date,Campaign Title,ASIN,Clicks,Shipped Items,Revenue,Commission Rate,Commission Income,Store Id,Tracking Id\r | 11-Nov-2026,\"💥10% Commmission｜Join the Success","updated_at":"202

## showingtime (day 2026-11-13) -> OK
detail: 2026-11-12 total showings=2390 (first seen 2026-11-13T11:45:43Z); agent decision=SILENT_PRESENT
query show: pulse_showings_daily?select=obs_date,showings,source,first_seen_at&is_total=eq.true&obs_date=eq.2026-11-12
query attempts: st_session_attempts?select=outcome,trigger,started_at,rows,dates_failed&attempt_date=eq.2026-11-13&order=started_at.desc&limit=5
query log:agent: /tmp/st-login-agent.log ~ /^2026-11-13 [0-9:]{8} decision=[A-Z_]+ yesterday=2026-11-12 /
rows show: 1
rows attempts: 1
sample show: [{"obs_date":"2026-11-12","showings":2390,"source":"showingtime","first_seen_at":"2026-11-13T11:45:43.145428+00:00"}]
sample attempts: [{"outcome":"login_ok","trigger":"alarm","started_at":"2026-11-13T11:45:34.264+00:00","rows":174,"dates_failed":0}]
log agent: 2026-11-13 07:05:04 decision=SILENT_PRESENT yesterday=2026-11-12 present=1 ext_last_outcome_today=login_ok

## realtea-generate (day 2026-11-09) -> OK
detail: issue #71 week_end 2026-11-08 generated 2026-11-09T13:31:35Z
query issue: pulse_newsletter_issues?select=issue_no,week_end,status,created_at,generated_at:content->substack->>generatedAt&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&week_end=eq.2026-11-08
query runs: monday_run_reports?select=status,issue_no,gate_blocked_reason,failure_reason,auto_refired_at,started_at,finished_at&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&week_end=eq.2026-11-08&order=started_at.desc&limit=3
rows issue: 1
rows runs: 3
sample issue: [{"issue_no":71,"week_end":"2026-11-08","status":"draft","created_at":"2026-11-09T13:31:35.324168+00:00","generated_at":"2026-11-09T13:31:35.504Z"}]
sample runs: [{"status":"complete","issue_no":71,"gate_blocked_reason":null,"failure_reason":null,"auto_refired_at":null,"started_at":"2026-11-09T13:23:37.315526+00:00","finished_at":"2026-11-09T13:34:08.065+00:00"},{"status":"complete","issue_no":70,"gate_blocked_reason":null,"failure_reason":null,"auto_refired_at":null,"started_at":"2026-11-09T11:30:07.757242+00:00","finished_at":"2026-11-09T11:34:36.829+00:00"},{"status":"complete","issue_no":70,"gate_blocked_reason":null,"failure_reason":null,"auto_refired_at":null,"started_at":"2026-11-09T10:30:19.367438+00:00","finished_at":"2026-11-09T11:29:00.668+0

## realtea-publish (day 2026-11-09) -> OK
detail: issue #71 published: https://uncommonagent.substack.com/p/realtea-roundup-71
query issue: pulse_newsletter_issues?select=issue_no,week_end,generated_at:content->substack->>generatedAt,substack_url:content->>substackUrl&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&week_end=eq.2026-11-08
rows issue: 1
sample issue: [{"issue_no":71,"week_end":"2026-11-08","generated_at":"2026-11-09T13:31:35.504Z","substack_url":"https://uncommonagent.substack.com/p/realtea-roundup-71"}]

# Job incident - showingtime - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 13:25 ET.

## Failure
not OK by 12:45: 2026-11-12 missing; last session otp_timeout/alarm at 2026-11-13T11:31:12Z (dates_failed 8); agent decision=ACT_OTP_TIMEOUT

## Cause
The 2026-11-12 showings are missing because every ShowingTime session today stopped at the 2FA screen and no code came in. The extension logged in, hit the OTP prompt, and polled the server OTP endpoint (it reads the code from Gmail; background.js:456-473, 677-680), but no code arrived in time. Both attempts recorded otp_timeout with rows=0 and dates_failed=8: the 11:31Z alarm and the 17:30Z failed_retry. The 07:05 agent mapped that outcome to ACT_OTP_TIMEOUT (agent-decide.sh:32). Its gesture-login fallback reached the same OTP screen and got no code (07:11:09). Code and rows agree, and the same failure on two triggers six hours apart is not a one-off. The block is ShowingTime 2FA code delivery or the Gmail OTP source, which is a protected credential/2FA area. Proving any fix would also need a live ShowingTime login. Side note: the attempt detail says "within 300 s", but the code cap is OTP_POLL_CAP_MS=120000 (background.js:50). That is a reporting mismatch, not the cause.

## Evidence
- st_session_attempts 2026-11-13T11:31:12Z outcome=otp_timeout trigger=alarm rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- st_session_attempts 2026-11-13T17:30:40Z outcome=otp_timeout trigger=failed_retry rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- pulse_showings_daily obs_date=2026-11-12 is_total=true: 0 rows
- st-login-agent.log '2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout'
- st-login-agent.log '2026-11-13 07:11:09 recheck yesterday=2026-11-12 present=0 after gesture login: OTP screen, no code'
- tools/login-agent/agent-decide.sh:32 otp_timeout -> ACT_OTP_TIMEOUT
- tools/showings-daily-pull/background.js:50 OTP_POLL_CAP_MS=120000; :456-473 pollForOtp polls the server otp-latest endpoint (Gmail-sourced); :677-680 OTP prompt detected, no code -> throw
- tools/showings-daily-pull/pull-core.js:337-339 otpLatestUrlFrom derives /api/showingtime/otp-latest

## Decision
ESCALATED (protected action): ShowingTime 2FA codes aren't arriving (both of today's logins hit the code screen and got nothing): can you check that ST is still sending its codes to the Gmail the server reads, and log in once by hand?
- confidence: high; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:46:56Z)
- query show: `pulse_showings_daily?select=obs_date,showings,source,first_seen_at&is_total=eq.true&obs_date=eq.2026-11-12`
- query attempts: `st_session_attempts?select=outcome,trigger,started_at,rows,dates_failed&attempt_date=eq.2026-11-13&order=started_at.desc&limit=5`
- query log:agent: `/Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/st-login-agent.log ~ /^2026-11-13 [0-9:]{8} decision=[A-Z_]+ yesterday=2026-11-12 /`

```json
{
  "verdict": "retrying",
  "detail": "2026-11-12 missing; last session otp_timeout/alarm at 2026-11-13T11:31:12Z (dates_failed 8); agent decision=ACT_OTP_TIMEOUT",
  "rows": {
    "show": 0,
    "attempts": 2
  },
  "sample": {
    "show": [],
    "attempts": [
      {
        "outcome": "otp_timeout",
        "trigger": "alarm",
        "started_at": "2026-11-13T11:31:12Z",
        "rows": 0,
        "dates_failed": 8,
        "detail": "2FA prompt shown; no code arrived within 300 s"
      },
      {
        "outcome": "otp_timeout",
        "trigger": "failed_retry",
        "started_at": "2026-11-13T17:30:40Z",
        "rows": 0,
        "dates_failed": 8,
        "detail": "2FA prompt shown; no code arrived within 300 s"
      }
    ]
  },
  "log": {
    "agent": [
      "2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout"
    ]
  }
}
```

## Diagnose rows
```json
{
  "queries": {
    "log:agent_tail": "/Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/st-login-agent.log ~ /^2026-11-13 /"
  },
  "rows": {},
  "logs": {
    "agent_tail": [
      "2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout",
      "2026-11-13 07:11:09 recheck yesterday=2026-11-12 present=0 after gesture login: OTP screen, no code"
    ]
  }
}
```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-jobs/home/job-fixes/showingtime-2026-11-13/handoff/evidence-showingtime-2026-11-13.json

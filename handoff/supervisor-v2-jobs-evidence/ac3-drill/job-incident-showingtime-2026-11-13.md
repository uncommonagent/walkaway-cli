# Job incident - showingtime - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:22 ET.

## Failure
not OK by 12:45: 2026-11-12 missing; last session otp_timeout/alarm at 2026-11-13T11:31:12Z (dates_failed 8); agent decision=ACT_OTP_TIMEOUT

## Cause
Yesterday's (2026-11-12) showings total never landed because every ShowingTime login on 2026-11-13 stopped at the 2FA screen. Both extension sessions show outcome=otp_timeout: the 11:31:12Z alarm run and the 17:30:40Z failed_retry run, each with rows=0, dates_failed=8 and "2FA prompt shown; no code arrived within 300 s". The 07:05 agent read that state and chose ACT_OTP_TIMEOUT (agent-decide.sh:32). Its gesture login at 07:11:09 ended the same way: "OTP screen, no code". In the code, background.js:672-680 sees the Verify2FA #Code field and polls the server OTP endpoint, which reads the code from Gmail (background.js:13, 455-473). The poll finds no code, it throws "OTP prompt appeared but no code arrived within the cap", and pull-core.js:465 maps that to otp_timeout. The pull and ingest code is working as designed. The failure is that the 2FA code is not reaching the Gmail-backed OTP endpoint, or ShowingTime is no longer sending it. Fixing or checking that means ShowingTime 2FA, credentials and a live login, which are PROTECTED. One small mismatch for later: the session detail says 300 s, but OTP_POLL_CAP_MS at background.js:50 is 120000. It does not change the cause.

## Evidence
- st_session_attempts 2026-11-13T11:31:12Z outcome=otp_timeout trigger=alarm rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- st_session_attempts 2026-11-13T17:30:40Z outcome=otp_timeout trigger=failed_retry rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- pulse_showings_daily is_total=true obs_date=2026-11-12: 0 rows
- log: 2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout
- log: 2026-11-13 07:11:09 recheck yesterday=2026-11-12 present=0 after gesture login: OTP screen, no code
- tools/login-agent/agent-decide.sh:32 otp_timeout -> ACT_OTP_TIMEOUT
- tools/showings-daily-pull/background.js:672-680 2FA branch throws 'OTP prompt appeared but no code arrived within the cap'
- tools/showings-daily-pull/background.js:455-473 polls the server OTP endpoint (Gmail-backed, per background.js:13) until a code appears or the cap runs out (OTP_POLL_CAP_MS=120000 at :50)
- tools/showings-daily-pull/pull-core.js:465 maps that message to otp_timeout

## Decision
ESCALATED (protected action): ShowingTime's 2FA code never reached the OTP endpoint on 11/13. Can you log in by hand and check that the code email still reaches Gmail? (yes / no, the 2FA phone or email changed)
- confidence: high; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:46:58Z)
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

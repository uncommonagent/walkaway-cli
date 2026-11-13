# Job incident - showingtime - 2026-11-13

Written by the walkaway job operator (read-only diagnosis) at 2026-11-13 12:51 ET.

## Failure
not OK by 12:45: 2026-11-12 missing; last session otp_timeout/alarm at 2026-11-13T11:31:12Z (dates_failed 8); agent decision=ACT_OTP_TIMEOUT

## Cause
Yesterday's showings (2026-11-12) are missing because ShowingTime's login asked for a 2FA code three times today and no code ever arrived. The code is doing what it was built to do. At 11:31Z the extension's alarm pull logged in, hit an OTP prompt, and found no code within the 300 s cap. tools/showings-daily-pull/background.js:677-680 then threw "OTP prompt appeared but no code arrived within the cap". classifyLoginError (pull-core.js:465) recorded that as otp_timeout. The 07:05 agent read it and decided ACT_OTP_TIMEOUT (agent-decide.sh:32). Its gesture login at 07:11 hit the same OTP screen with no code. The 17:30Z failed_retry failed the same way, with rows=0 and dates_failed=8 both times. Normally the extension logs in with no 2FA, so ShowingTime is now demanding a code that is not reaching the OTP inbox the extension polls. That is about credentials and 2FA delivery, which is protected and needs a human. No change in the repo can fix it.

## Evidence
- st_session_attempts 2026-11-13T11:31:12Z outcome=otp_timeout trigger=alarm rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- st_session_attempts 2026-11-13T17:30:40Z outcome=otp_timeout trigger=failed_retry rows=0 dates_failed=8 detail='2FA prompt shown; no code arrived within 300 s'
- pulse_showings_daily obs_date=2026-11-12 is_total=true: 0 rows
- log: 2026-11-13 07:05:04 decision=ACT_OTP_TIMEOUT yesterday=2026-11-12 present=0 ext_last_outcome_today=otp_timeout
- log: 2026-11-13 07:11:09 recheck yesterday=2026-11-12 present=0 after gesture login: OTP screen, no code
- tools/showings-daily-pull/background.js:677-680 needsOtp -> pollForOtp -> throw 'OTP prompt appeared but no code arrived within the cap'
- tools/showings-daily-pull/pull-core.js:464-465 classifyLoginError -> otp_timeout
- tools/login-agent/agent-decide.sh:32 otp_timeout -> ACT_OTP_TIMEOUT
- job notes: 'OTP / 2FA / ShowingTime credentials are PROTECTED: escalate'

## Decision
ESCALATED (protected action): ShowingTime asked for a 2FA code 3 times today and none arrived; can you log in by hand and check where the codes are going?
- confidence: high; protected_hit: true; needs_live_action: true

## Check rows (read-only, 2026-11-13T17:46:22Z)
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

# http re-pull path probe (pulse-daily-sync?ifMissing=1: skips when yesterday's snapshots are present; no write)
## call 1 via _http_get (30 s client timeout)
[2026-11-15 12:23:36] http GET https://throughlinepro.com/api/cron/pulse-daily-sync?ifMissing=1 -> HTTP 000 
## call 2 (60 s timeout, curl exit code captured; Bearer CRON_SECRET via stdin)
2026-11-15 12:25:31 HTTP 200 after 42.8 s: {"teams":1,"skipped":"yesterday's snapshots already present"}
## pulse_sync_state after both calls (read-only): [{"updated_at":"2026-11-15T08:18:32.36507+00:00","last_delta_ts":"2026-11-15T06:30:18+00:00","status":"ok"}]
-> the route skipped both times; no sync ran (updated_at unchanged 08:18:32Z). Call 1 read HTTP 000 = curl timeout (exit 28) at 30 s: fixed in _http_get (exit 28 = delivered/still running; other curl errors = failed try; default timeout 60 s).

# Data incident - drill-lost - 2026-11-18

Written by the walkaway data operator (read-only) at 2026-11-15 13:13 ET.

## Gaps
- 2026-11-16: missing - rows 0 / floor 4 (rows when opened: 0); no re-pull path for age 2 (source cannot re-pull a past period); last try: none

## Cause
(no diagnosis: deterministic decision)

## Evidence

## Decision
ESCALATED (lost data): drill-lost lost 2026-11-16 (0/4 rows): the source cannot re-pull a past day. Accept the loss, or fix the pull so it stops missing days?
- confidence: -; protected_hit: -; needs_live_action: -

## Fresh read-only counts (2026-11-18 12:30 EST)
```json
[
  {
    "period": "2026-11-18",
    "key": "2026-11-18",
    "status": "not_ready",
    "count": null
  },
  {
    "period": "2026-11-17",
    "key": "2026-11-17",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-16",
    "key": "2026-11-16",
    "status": "missing",
    "count": 0
  },
  {
    "period": "2026-11-15",
    "key": "2026-11-15",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-14",
    "key": "2026-11-14",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-13",
    "key": "2026-11-13",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-12",
    "key": "2026-11-12",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-11",
    "key": "2026-11-11",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-10",
    "key": "2026-11-10",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-09",
    "key": "2026-11-09",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-08",
    "key": "2026-11-08",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-07",
    "key": "2026-11-07",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-06",
    "key": "2026-11-06",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-05",
    "key": "2026-11-05",
    "status": "ok",
    "count": 4
  },
  {
    "period": "2026-11-04",
    "key": "2026-11-04",
    "status": "ok",
    "count": 4
  }
]
```

## Re-pull log (supervisor)
```

```

Full evidence: /Users/jimross/Projects/walkaway-cli/tests/drill/work-data/home/data-fixes/drill-lost-2026-11-18/handoff/evidence-drill-lost-2026-11-18.json

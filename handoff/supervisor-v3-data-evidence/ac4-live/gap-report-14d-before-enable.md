# data/series.yaml check dump - 2026-11-15 12:22 EST (read-only REST GETs, exact counts; keys never printed)

## amz-tracking-offsite (as of 2026-11-15 12:22 EST) -> PASS
table: amazon_tracking_daily.date (date, daily)  floor: 13 (50% of 30-day median 27 (range 21..41))  last complete: 2026-11-14
query (newest period): amazon_tracking_daily?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&store_id=eq.offsite&date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=39
  2026-11-13 key=2026-11-13 age=2 ok rows=39
  2026-11-12 key=2026-11-12 age=3 ok rows=41
  2026-11-11 key=2026-11-11 age=4 ok rows=40
  2026-11-10 key=2026-11-10 age=5 ok rows=34
  2026-11-09 key=2026-11-09 age=6 ok rows=32
  2026-11-08 key=2026-11-08 age=7 ok rows=28
  2026-11-07 key=2026-11-07 age=8 ok rows=29
  2026-11-06 key=2026-11-06 age=9 ok rows=30
  2026-11-05 key=2026-11-05 age=10 ok rows=30
  2026-11-04 key=2026-11-04 age=11 ok rows=25
  2026-11-03 key=2026-11-03 age=12 ok rows=28
  2026-11-02 key=2026-11-02 age=13 ok rows=24
  2026-11-01 key=2026-11-01 age=14 ok rows=25

## amz-tracking-onsite (as of 2026-11-15 12:22 EST) -> PASS
table: amazon_tracking_daily.date (date, daily)  floor: 2 (structural: all 30 days = 2)  last complete: 2026-11-14
query (newest period): amazon_tracking_daily?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&store_id=eq.onsite&date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=2
  2026-11-13 key=2026-11-13 age=2 ok rows=2
  2026-11-12 key=2026-11-12 age=3 ok rows=2
  2026-11-11 key=2026-11-11 age=4 ok rows=2
  2026-11-10 key=2026-11-10 age=5 ok rows=2
  2026-11-09 key=2026-11-09 age=6 ok rows=2
  2026-11-08 key=2026-11-08 age=7 ok rows=2
  2026-11-07 key=2026-11-07 age=8 ok rows=2
  2026-11-06 key=2026-11-06 age=9 ok rows=2
  2026-11-05 key=2026-11-05 age=10 ok rows=2
  2026-11-04 key=2026-11-04 age=11 ok rows=2
  2026-11-03 key=2026-11-03 age=12 ok rows=2
  2026-11-02 key=2026-11-02 age=13 ok rows=2
  2026-11-01 key=2026-11-01 age=14 ok rows=2

## amz-creator-connections (as of 2026-11-15 12:22 EST) -> PASS
table: amazon_creator_connections_daily.date (date, daily)  floor: 3 (50% of 30-day median 7 (range 1..88))  last complete: 2026-11-13
query (newest period): amazon_creator_connections_daily?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&date=eq.2026-11-13
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 not_ready
  2026-11-13 key=2026-11-13 age=2 ok rows=8
  2026-11-12 key=2026-11-12 age=3 ok rows=8
  2026-11-11 key=2026-11-11 age=4 ok rows=9
  2026-11-10 key=2026-11-10 age=5 ok rows=8
  2026-11-09 key=2026-11-09 age=6 ok rows=9
  2026-11-08 key=2026-11-08 age=7 ok rows=8
  2026-11-07 key=2026-11-07 age=8 ok rows=7
  2026-11-06 key=2026-11-06 age=9 ok rows=5
  2026-11-05 key=2026-11-05 age=10 ok rows=7
  2026-11-04 key=2026-11-04 age=11 ok rows=84
  2026-11-03 key=2026-11-03 age=12 ok rows=72
  2026-11-02 key=2026-11-02 age=13 ok rows=8
  2026-11-01 key=2026-11-01 age=14 ok rows=5

## amz-sponsored-products (as of 2026-11-15 12:22 EST) -> PASS
table: amazon_sponsored_products_daily.date (date, daily)  floor: 38 (50% of 30-day median 77 (range 49..110))  last complete: 2026-11-13
query (newest period): amazon_sponsored_products_daily?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&date=eq.2026-11-13
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 not_ready
  2026-11-13 key=2026-11-13 age=2 ok rows=107
  2026-11-12 key=2026-11-12 age=3 ok rows=96
  2026-11-11 key=2026-11-11 age=4 ok rows=81
  2026-11-10 key=2026-11-10 age=5 ok rows=65
  2026-11-09 key=2026-11-09 age=6 ok rows=77
  2026-11-08 key=2026-11-08 age=7 ok rows=102
  2026-11-07 key=2026-11-07 age=8 ok rows=96
  2026-11-06 key=2026-11-06 age=9 ok rows=84
  2026-11-05 key=2026-11-05 age=10 ok rows=77
  2026-11-04 key=2026-11-04 age=11 ok rows=91
  2026-11-03 key=2026-11-03 age=12 ok rows=77
  2026-11-02 key=2026-11-02 age=13 ok rows=74
  2026-11-01 key=2026-11-01 age=14 ok rows=75

## amz-connect-summary (as of 2026-11-15 12:22 EST) -> PASS
table: amazon_connect_summary_daily.date (date, daily)  floor: 2 (structural: all 30 days = 2 (one row per program))  last complete: 2026-11-14
query (newest period): amazon_connect_summary_daily?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=2
  2026-11-13 key=2026-11-13 age=2 ok rows=2
  2026-11-12 key=2026-11-12 age=3 ok rows=2
  2026-11-11 key=2026-11-11 age=4 ok rows=2
  2026-11-10 key=2026-11-10 age=5 ok rows=2
  2026-11-09 key=2026-11-09 age=6 ok rows=2
  2026-11-08 key=2026-11-08 age=7 ok rows=2
  2026-11-07 key=2026-11-07 age=8 ok rows=2
  2026-11-06 key=2026-11-06 age=9 ok rows=2
  2026-11-05 key=2026-11-05 age=10 ok rows=2
  2026-11-04 key=2026-11-04 age=11 ok rows=2
  2026-11-03 key=2026-11-03 age=12 ok rows=2
  2026-11-02 key=2026-11-02 age=13 ok rows=2
  2026-11-01 key=2026-11-01 age=14 ok rows=2

## markable-spend (as of 2026-11-15 12:22 EST) -> PASS
table: markable_spend_daily.report_date (date, daily)  floor: 1 (structural: all 30 days = 1)  last complete: 2026-11-14
query (newest period): markable_spend_daily?select=report_date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&report_date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=1
  2026-11-13 key=2026-11-13 age=2 ok rows=1
  2026-11-12 key=2026-11-12 age=3 ok rows=1
  2026-11-11 key=2026-11-11 age=4 ok rows=1
  2026-11-10 key=2026-11-10 age=5 ok rows=1
  2026-11-09 key=2026-11-09 age=6 ok rows=1
  2026-11-08 key=2026-11-08 age=7 ok rows=1
  2026-11-07 key=2026-11-07 age=8 ok rows=1
  2026-11-06 key=2026-11-06 age=9 ok rows=1
  2026-11-05 key=2026-11-05 age=10 ok rows=1
  2026-11-04 key=2026-11-04 age=11 ok rows=1
  2026-11-03 key=2026-11-03 age=12 ok rows=1
  2026-11-02 key=2026-11-02 age=13 ok rows=1
  2026-11-01 key=2026-11-01 age=14 ok rows=1

## meta-daily-metrics (as of 2026-11-15 12:22 EST) -> PASS
table: meta_daily_metrics.date (date, daily)  floor: 1 (50% of 30-day median 3 (range 3..9))  last complete: 2026-11-14
query (newest period): meta_daily_metrics?select=date&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=8
  2026-11-13 key=2026-11-13 age=2 ok rows=9
  2026-11-12 key=2026-11-12 age=3 ok rows=9
  2026-11-11 key=2026-11-11 age=4 ok rows=9
  2026-11-10 key=2026-11-10 age=5 ok rows=7
  2026-11-09 key=2026-11-09 age=6 ok rows=7
  2026-11-08 key=2026-11-08 age=7 ok rows=3
  2026-11-07 key=2026-11-07 age=8 ok rows=3
  2026-11-06 key=2026-11-06 age=9 ok rows=3
  2026-11-05 key=2026-11-05 age=10 ok rows=3
  2026-11-04 key=2026-11-04 age=11 ok rows=3
  2026-11-03 key=2026-11-03 age=12 ok rows=3
  2026-11-02 key=2026-11-02 age=13 ok rows=3
  2026-11-01 key=2026-11-01 age=14 ok rows=3

## st-showings-daily (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_showings_daily.obs_date (date, daily)  floor: 1 (structural: one is_total row per day, all 30 days)  last complete: 2026-11-13
query (newest period): pulse_showings_daily?select=obs_date&is_total=eq.true&obs_date=eq.2026-11-13
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 not_ready
  2026-11-13 key=2026-11-13 age=2 ok rows=1
  2026-11-12 key=2026-11-12 age=3 ok rows=1
  2026-11-11 key=2026-11-11 age=4 ok rows=1
  2026-11-10 key=2026-11-10 age=5 ok rows=1
  2026-11-09 key=2026-11-09 age=6 ok rows=1
  2026-11-08 key=2026-11-08 age=7 ok rows=1
  2026-11-07 key=2026-11-07 age=8 ok rows=1
  2026-11-06 key=2026-11-06 age=9 ok rows=1
  2026-11-05 key=2026-11-05 age=10 ok rows=1
  2026-11-04 key=2026-11-04 age=11 ok rows=1
  2026-11-03 key=2026-11-03 age=12 ok rows=1
  2026-11-02 key=2026-11-02 age=13 ok rows=1
  2026-11-01 key=2026-11-01 age=14 ok rows=1

## bb-showings-daily (as of 2026-11-15 12:22 EST) -> GAPS 5
table: pulse_bb_showings_daily.obs_date (date, daily)  floor: 10 (50% of 30-day median 21 (range 19..21))  last complete: 2026-11-08
query (newest period): pulse_bb_showings_daily?select=obs_date&is_total=eq.true&obs_date=eq.2026-11-13
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 not_ready
  2026-11-13 key=2026-11-13 age=2 missing rows=0
  2026-11-12 key=2026-11-12 age=3 missing rows=0
  2026-11-11 key=2026-11-11 age=4 missing rows=0
  2026-11-10 key=2026-11-10 age=5 missing rows=0
  2026-11-09 key=2026-11-09 age=6 missing rows=0
  2026-11-08 key=2026-11-08 age=7 ok rows=21
  2026-11-07 key=2026-11-07 age=8 ok rows=21
  2026-11-06 key=2026-11-06 age=9 ok rows=21
  2026-11-05 key=2026-11-05 age=10 ok rows=21
  2026-11-04 key=2026-11-04 age=11 ok rows=21
  2026-11-03 key=2026-11-03 age=12 ok rows=21
  2026-11-02 key=2026-11-02 age=13 ok rows=21
  2026-11-01 key=2026-11-01 age=14 ok rows=21
gaps: 2026-11-13 (missing 0), 2026-11-12 (missing 0), 2026-11-11 (missing 0), 2026-11-10 (missing 0), 2026-11-09 (missing 0)

## st-showings-forward (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_showings_forward.snapshot_date (date, daily)  floor: 4 (structural: all 27 days = 4 (horizons 0..3))  last complete: 2026-11-14
query (newest period): pulse_showings_forward?select=snapshot_date&is_total=eq.true&snapshot_date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=4
  2026-11-13 key=2026-11-13 age=2 ok rows=4
  2026-11-12 key=2026-11-12 age=3 ok rows=4
  2026-11-11 key=2026-11-11 age=4 ok rows=4
  2026-11-10 key=2026-11-10 age=5 ok rows=4
  2026-11-09 key=2026-11-09 age=6 ok rows=4
  2026-11-08 key=2026-11-08 age=7 ok rows=4
  2026-11-07 key=2026-11-07 age=8 ok rows=4
  2026-11-06 key=2026-11-06 age=9 ok rows=4
  2026-11-05 key=2026-11-05 age=10 ok rows=4
  2026-11-04 key=2026-11-04 age=11 ok rows=4
  2026-11-03 key=2026-11-03 age=12 ok rows=4
  2026-11-02 key=2026-11-02 age=13 ok rows=4
  2026-11-01 key=2026-11-01 age=14 ok rows=4

## pulse-daily-snapshots (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_daily_snapshots.snapshot_date (date, daily)  floor: 1 (structural: one central_oh row per day, all 30 days)  last complete: 2026-11-14
query (newest period): pulse_daily_snapshots?select=snapshot_date&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&geo_type=eq.central_oh&snapshot_date=eq.2026-11-14
  2026-11-15 key=2026-11-15 age=0 not_ready
  2026-11-14 key=2026-11-14 age=1 ok rows=1
  2026-11-13 key=2026-11-13 age=2 ok rows=1
  2026-11-12 key=2026-11-12 age=3 ok rows=1
  2026-11-11 key=2026-11-11 age=4 ok rows=1
  2026-11-10 key=2026-11-10 age=5 ok rows=1
  2026-11-09 key=2026-11-09 age=6 ok rows=1
  2026-11-08 key=2026-11-08 age=7 ok rows=1
  2026-11-07 key=2026-11-07 age=8 ok rows=1
  2026-11-06 key=2026-11-06 age=9 ok rows=1
  2026-11-05 key=2026-11-05 age=10 ok rows=1
  2026-11-04 key=2026-11-04 age=11 ok rows=1
  2026-11-03 key=2026-11-03 age=12 ok rows=1
  2026-11-02 key=2026-11-02 age=13 ok rows=1
  2026-11-01 key=2026-11-01 age=14 ok rows=1

## pulse-odds-snapshots (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_odds_snapshots.snapshot_date (date, daily)  floor: 22 (50% of 43: 43 every day for the last 27 days, but the count is not structural (one row per market; 2026-10-05..10-11 had 3), so the 50% rule applies)  last complete: 2026-11-15
query (newest period): pulse_odds_snapshots?select=snapshot_date&snapshot_date=eq.2026-11-15
  2026-11-15 key=2026-11-15 age=0 ok rows=43
  2026-11-14 key=2026-11-14 age=1 ok rows=43
  2026-11-13 key=2026-11-13 age=2 ok rows=43
  2026-11-12 key=2026-11-12 age=3 ok rows=43
  2026-11-11 key=2026-11-11 age=4 ok rows=43
  2026-11-10 key=2026-11-10 age=5 ok rows=43
  2026-11-09 key=2026-11-09 age=6 ok rows=43
  2026-11-08 key=2026-11-08 age=7 ok rows=43
  2026-11-07 key=2026-11-07 age=8 ok rows=43
  2026-11-06 key=2026-11-06 age=9 ok rows=43
  2026-11-05 key=2026-11-05 age=10 ok rows=43
  2026-11-04 key=2026-11-04 age=11 ok rows=43
  2026-11-03 key=2026-11-03 age=12 ok rows=43
  2026-11-02 key=2026-11-02 age=13 ok rows=43
  2026-11-01 key=2026-11-01 age=14 ok rows=43

## pulse-events-refresh (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_events_refresh_runs.ran_at (timestamp, daily)  floor: 1 (structural: one run row per day, all 27 days)  last complete: 2026-11-15
query (newest period): pulse_events_refresh_runs?select=ran_at&ran_at=gte.2026-11-15T05:00:00Z&ran_at=lt.2026-11-16T05:00:00Z
  2026-11-15 key=2026-11-15 age=0 ok rows=1
  2026-11-14 key=2026-11-14 age=1 ok rows=1
  2026-11-13 key=2026-11-13 age=2 ok rows=1
  2026-11-12 key=2026-11-12 age=3 ok rows=1
  2026-11-11 key=2026-11-11 age=4 ok rows=1
  2026-11-10 key=2026-11-10 age=5 ok rows=1
  2026-11-09 key=2026-11-09 age=6 ok rows=1
  2026-11-08 key=2026-11-08 age=7 ok rows=1
  2026-11-07 key=2026-11-07 age=8 ok rows=1
  2026-11-06 key=2026-11-06 age=9 ok rows=1
  2026-11-05 key=2026-11-05 age=10 ok rows=1
  2026-11-04 key=2026-11-04 age=11 ok rows=1
  2026-11-03 key=2026-11-03 age=12 ok rows=1
  2026-11-02 key=2026-11-02 age=13 ok rows=1
  2026-11-01 key=2026-11-01 age=14 ok rows=1

## pulse-weekly-stats (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_weekly_stats.year_week (yearweek, weekly)  floor: 1 (structural: one central_oh row per week, all 8 weeks)  last complete: 2026-11-02
query (newest period): pulse_weekly_stats?select=year_week&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&geo_type=eq.central_oh&year_week=eq.202645
  2026-11-09 key=202646 age=0 not_ready
  2026-11-02 key=202645 age=1 ok rows=1
  2026-10-26 key=202644 age=2 ok rows=1
  2026-10-19 key=202643 age=3 ok rows=1
  2026-10-12 key=202642 age=4 ok rows=1

## pulse-signal-scores (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_signal_scores.year_week (yearweek, weekly)  floor: 264 (50% of 8-week median 528 (range 515..534))  last complete: 2026-11-02
query (newest period): pulse_signal_scores?select=year_week&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&year_week=eq.202645
  2026-11-09 key=202646 age=0 not_ready
  2026-11-02 key=202645 age=1 ok rows=529
  2026-10-26 key=202644 age=2 ok rows=529
  2026-10-19 key=202643 age=3 ok rows=534
  2026-10-12 key=202642 age=4 ok rows=530

## pulse-market-health (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_market_health_weekly.year_week (yearweek, weekly)  floor: 264 (50% of 8-week median 529 (range 517..536))  last complete: 2026-11-02
query (newest period): pulse_market_health_weekly?select=year_week&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&year_week=eq.202645
  2026-11-09 key=202646 age=0 not_ready
  2026-11-02 key=202645 age=1 ok rows=531
  2026-10-26 key=202644 age=2 ok rows=532
  2026-10-19 key=202643 age=3 ok rows=536
  2026-10-12 key=202642 age=4 ok rows=532

## tma-cohort-showings (as of 2026-11-15 12:22 EST) -> PASS
table: recap_cohort_showings.year_week (yearweek, weekly)  floor: 256 (50% of 8-week median 512 (range 456..586))  last complete: 2026-11-02
query (newest period): recap_cohort_showings?select=year_week&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&year_week=eq.202645
  2026-11-09 key=202646 age=0 not_ready
  2026-11-02 key=202645 age=1 ok rows=485
  2026-10-26 key=202644 age=2 ok rows=456
  2026-10-19 key=202643 age=3 ok rows=504
  2026-10-12 key=202642 age=4 ok rows=497

## pulse-showings-weekly (as of 2026-11-15 12:22 EST) -> PASS
table: pulse_showings_weekly.year_week (yearweek, weekly)  floor: 1 (structural: one row per week, all 8 weeks)  last complete: 2026-11-02
query (newest period): pulse_showings_weekly?select=year_week&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&year_week=eq.202645
  2026-11-09 key=202646 age=0 not_ready
  2026-11-02 key=202645 age=1 ok rows=1
  2026-10-26 key=202644 age=2 ok rows=1
  2026-10-19 key=202643 age=3 ok rows=1
  2026-10-12 key=202642 age=4 ok rows=1

## recap-reports (as of 2026-11-15 12:22 EST) -> PASS
table: report_pdfs.received_at (timestamp, weekly)  floor: 15 (50% of 8-week median 31 (weeks 202639..202646: 29..33; 202638 = 51))  last complete: 2026-11-09
query (newest period): report_pdfs?select=received_at&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&received_from_email=eq.recap-extension@showingtime.local&received_at=gte.2026-11-09T05:00:00Z&received_at=lt.2026-11-16T05:00:00Z
  2026-11-09 key=2026-11-09 age=0 ok rows=31
  2026-11-02 key=2026-11-02 age=1 ok rows=30
  2026-10-26 key=2026-10-26 age=2 ok rows=29
  2026-10-19 key=2026-10-19 age=3 ok rows=30
  2026-10-12 key=2026-10-12 age=4 ok rows=33

## curb-inquiry-results (as of 2026-11-15 12:23 EST) -> PASS
table: curb_inquiry_results.week_date (date, weekly)  floor: 1 (50% of 9-week median 2 (range 1..2))  last complete: 2026-11-09
query (newest period): curb_inquiry_results?select=week_date&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&week_date=eq.2026-11-09
  2026-11-09 key=2026-11-09 age=0 ok rows=2
  2026-11-02 key=2026-11-02 age=1 ok rows=2
  2026-10-26 key=2026-10-26 age=2 ok rows=2
  2026-10-19 key=2026-10-19 age=3 ok rows=2
  2026-10-12 key=2026-10-12 age=4 ok rows=1

## pulse-member-snapshots (as of 2026-11-15 12:23 EST) -> PASS
table: pulse_member_snapshots.snapshot_date (date, monthly)  floor: 5065 (50% of 3-month median 10131 (10082 / 10131 / 10161))  last complete: 2026-11-01
query (newest period): pulse_member_snapshots?select=snapshot_date&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&snapshot_date=eq.2026-11-01
  2026-11-01 key=2026-11-01 age=0 ok rows=10161
  2026-10-01 key=2026-10-01 age=1 ok rows=10131
  2026-09-01 key=2026-09-01 age=2 ok rows=10082

## amz-tracking-offsite-today - EXCLUDED: evening intra-day pull of today into amazon_tracking_daily; the next morning's D-1 pull replaces it (amazon-ingest.ts:24-31) (covered by: amz-tracking-offsite)
probe: extension_report_state?select=report_type,last_success_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&report_type=eq.tracking_offsite_today
probe row: {"report_type":"tracking_offsite_today","last_success_at":"2026-11-15T01:13:56.985+00:00"}

## amz-bounties - EXCLUDED: a no-data day writes no rows by design (ingest/amazon/route.ts:158-183; 6 row-days in 30), so a missing day is indistinguishable from zero bounties (covered by: jobs.yaml extension-reports (bounty success within 26 h))
probe: amazon_bounties_daily?select=date,created_at&user_id=eq.d3a83609-87a8-46aa-aa74-a2105d275748&order=date.desc&limit=1
probe row: {"date":"2026-11-13","created_at":"2026-11-14T12:36:31.866255+00:00"}

## amz-self-heal - EXCLUDED: the extension's repair loop (heal-lib.js), not a pull of its own (covered by: it is the self_heal re-pull path of amz-tracking-* and amz-sponsored-products)

## sr-daily-digest - EXCLUDED: Vercel cron that sends the morning email (send, not a pull) (covered by: -)

## sr-evening-digest - EXCLUDED: Vercel cron that sends the evening email; its ordered_preview_log row is derived and only written when ordered > 0 (covered by: -)

## idea-list-asin-stats - EXCLUDED: manual popup refresh, no scheduler (background.js:1610); one row per ASIN, not dated (covered by: -)

## cc-optin-am - EXCLUDED: live opt-in action, not a data pull (covered by: jobs.yaml cc-optin-am)

## cc-optin-pm - EXCLUDED: live opt-in action (PM session off since 10/31) (covered by: jobs.yaml cc-optin-pm (disabled))

## spc-optin - EXCLUDED: live opt-in action, not a data pull (covered by: jobs.yaml spc)

## bf-daily - EXCLUDED: list build/publish action, not a data pull (covered by: jobs.yaml bf-daily)

## st-session-state - EXCLUDED: st_session_attempts is an attempt ledger (table exists since 11-13) (covered by: jobs.yaml showingtime)
probe: st_session_attempts?select=attempt_date,outcome,trigger,started_at&team_id=eq.d14dce4f-9111-45e7-a52d-18d5f6dd04b6&order=started_at.desc&limit=1
probe row: {"attempt_date":"2026-11-15","outcome":"ok","trigger":"url","started_at":"2026-11-15T16:57:21.614+00:00"}

## st-listing-refresh - EXCLUDED: 2-minute single-listing job queue (background.js:44-45), no dated rows (covered by: -)

## pulse-macro-series - EXCLUDED: release-driven observations (FRED etc.), no per-day expectation (covered by: pulse-odds-snapshots (the same pulse-macro cron's daily run))
probe: pulse_macro_series?select=series_id,obs_date&order=obs_date.desc&limit=1
probe row: {"series_id":"affordability_athens","obs_date":"2026-11-15"}

## pulse-revision-sweep - EXCLUDED: rotating repair of 1-6-month-old snapshots, no dated output (covered by: -)

## pulse-reconcile - EXCLUDED: reconcile stamp + fact statuses, no dated output (covered by: -)

## showingtime-maintenance - EXCLUDED: deletes/reaps jobs and photo cache (covered by: -)

## pulse-events - EXCLUDED: Monday reminder send (covered by: -)

## daily-pulse-brief - EXCLUDED: brief send (PROTECTED send), not a data pull (covered by: -)
probe: pulse_brief_sends?select=send_date&order=send_date.desc&limit=1
probe row: {"send_date":"2026-11-15"}

## recap-offer-sync - EXCLUDED: offers upsert, not dated (covered by: -)

## offer-inbox-scan - EXCLUDED: inbox scan every 5 min; rows depend on incoming mail (covered by: -)

## gmail-poll - EXCLUDED: inbox scan every 5 min (ST PDFs); rows depend on incoming mail (covered by: -)

## field-guide-dispatch - EXCLUDED: lead queue every 5 min (covered by: -)

## monday-autorun - EXCLUDED: newsletter generation (Inngest), not a pull (covered by: jobs.yaml realtea-generate)

## monday-fallback - EXCLUDED: launchd fallback for generation (covered by: jobs.yaml realtea-generate)

## substack-publisher - EXCLUDED: publish (PROTECTED) (covered by: jobs.yaml realtea-publish)

## st-login-agent - EXCLUDED: launchd login/decision agent; reads, triggers the ST pull (covered by: jobs.yaml showingtime)

## offer-tracker - EXCLUDED: launchd plist in repo, not installed in ~/Library/LaunchAgents (covered by: -)

## inngest-unregistered - EXCLUDED: pulse-nightly, pulse-macro, pulse-events, spark-sync exist in inngest/functions but are not registered (app/api/inngest/route.ts serves only mondayAutorun) (covered by: -)

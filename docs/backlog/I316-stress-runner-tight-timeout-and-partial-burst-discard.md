---
id: I316
title: Stress test runner — tight notification-throughput timeout + partial bursts discarded
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-01
fixed_in: ce65141
related: [I040]
---

## Symptom

Two latent bugs in the example app's
`StressTestRunner.runNotificationThroughput`, both exposed by the
post-I040 fix landing the actual delivery semantics for iOS server
notifications:

1. **Too-tight timeout.** The budget `Duration(milliseconds: count + 1000)`
   sized for 1 ms / notification + 1 s overhead. Sized for the pre-I040
   fire-and-forget regime where `notify` resolved instantly regardless
   of delivery. Post-I040 iOS delivers at ~2–3 ms / notification
   (queue-drain bound). Counts ≥ 500 ran out of budget mid-burst.

2. **Partial bursts discarded entirely.** Selection logic at lines
   504–508 only considered a burst-id "winning" if it accumulated ≥
   `count` arrivals. When the timeout fired before any burst hit the
   threshold, `winningBurstId` stayed null, `winnerLatencies` was
   empty, and ALL received notifications got reclassified as
   `NotificationTimeout`. A burst that delivered 950 / 1000 reported
   the same as one that delivered 0 / 1000 — masking real progress
   under load.

Reproduction: Android client → iOS server → notification-throughput
stress test with `count: 1000`. Observed result: 1000 timeouts,
0 successes. Actual on-the-air delivery: most or all of the 1000
notifications arrived, but the test couldn't tell. Confirmed with
`count: 100`: passed cleanly (100 arrivals within the budget).

## Location

`bluey/example/lib/features/stress_tests/infrastructure/stress_test_runner.dart`
— `runNotificationThroughput`, around the now-replaced lines 492–512.
`bluey/example/lib/features/stress_tests/domain/stress_test_config.dart`
— `NotificationThroughputConfig` (added `timeout` field).

## Root cause

Bug 1: the timeout heuristic was tuned for the pre-I040 throughput
profile where `notify` returned `false` instantly under TX
backpressure (drop-and-pretend). The example app got "1 ms /
notification" because most weren't actually delivered. Post-I040 the
loop is BLE-air-rate-bound and the budget is 5–10× too small.

Bug 2: the selection logic conflated "no burst hit the count
threshold" with "no useful data received." The two are different —
the former is a question of whether the timeout fired vs. the
streaming completer; the latter is a question of whether any
notifications arrived at all. The runner was over-eager about
filtering "stragglers."

## Notes

Fixed in `ce65141`. Two changes:

1. `NotificationThroughputConfig` gained an optional `Duration?
   timeout`. When null, the runner derives a default from
   `10 ms × count + 2000 ms` — 5× safety margin on the observed iOS
   rate plus 2 s prologue overhead. Tests inject tight values to
   exercise the timeout path quickly.

2. Selection logic replaced: instead of insisting a burst-id hit
   `count` to be considered a winner, the runner picks the burst-id
   with the most arrivals at result-collection time. The streaming
   fast-path (one burst-id hits count → completer fires early) is
   unchanged; the difference is only on the timeout path, which now
   reports `succeeded = received_count` and
   `failed = (config.count - received_count)` as
   `NotificationTimeout` failures rather than discarding everything.

Verification: 1 new test (partial burst — 3 of 5 with 200 ms timeout)
asserts the new shape. Existing 3 NotificationThroughput tests stay
intact — they emit ≥ `count` synchronously and trigger the fast-path
unchanged.

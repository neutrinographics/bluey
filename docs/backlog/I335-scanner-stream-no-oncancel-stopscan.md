---
id: I335
title: `BlueyScanner.scan()`'s returned stream does not stop the platform scan on cancel
category: bug
severity: medium
platform: domain
status: fixed
last_verified: 2026-05-15
related: [I334]
---

## Resolution (2026-05-15)

Closed by the stream-conventions sweep on branch
`feature/stream-conventions`. Per Convention 5 of the design,
`Scanner.scan()`'s returned `StreamController` now has
`onCancel: () => stop()`. Cancelling the subscription stops the
platform scan; `Scanner.stop()` stays for imperative use.

The consumer-side workaround in `gossip_bluey` (holding the
`Scanner` reference and calling `stop()` explicitly) can be removed.

## Symptom

`BlueyScanner.scan({List<UUID>? services, Duration? timeout})` (`bluey/lib/src/discovery/bluey_scanner.dart:117`) builds an internal `StreamController<ScanResult>` and pipes platform events into it. The returned `controller.stream` is what consumers `.listen(...)` on.

The controller has **no `onCancel` handler**. Consequence: when a consumer cancels its `StreamSubscription`, nothing in bluey is notified. The internal `_platformSubscription` keeps receiving platform events, `_isScanning` stays `true`, and **`_platform.stopScan()` is never invoked**. The radio keeps scanning until either:

- `scanner.stop()` is called explicitly, or
- the optional `timeout` argument fires its internal `Timer`, or
- the scanner is disposed.

In Dart's stream contract, cancelling the only subscription on a single-subscription stream (or all subscriptions on a broadcast stream) is the canonical signal to stop the underlying work. Consumers reasonably assume cancelling their listener stops the scan.

Reproduced 2026-05-14 in the `gossip_chat` dogfood app on Android: tapping "Start Discovery" then "Stop Discovery" left the radio scanning. App-side state flipped (`isDiscovering = false`), but bluey diagnostic logs continued to emit `DeviceDiscoveredEvent` and the platform was clearly still consuming radio. Worked around in `gossip_bluey` commit `6ab25a5` by stashing the `Scanner` instance returned by `_bluey.scanner()` and explicitly calling `scanner.stop()` in `stopScan`.

## Why this is a bluey bug

1. **Dart's stream-cancellation idiom is the natural "stop" signal.** Every other Dart API with a "subscribe to a stream of events backed by an expensive resource" pattern stops that resource on cancel (Firestore listeners, web sockets, platform sensors). `scan()` is the outlier.

2. **The current API forces consumers to hold the `Scanner` reference solely to call `stop()` later.** That's a strict superset of what `scan()` already lets them do (the `Scanner` instance and the returned `Stream` are 1:1; there's no reason to require both). It also means consumers who use the fluent `_bluey.scanner().scan(...)` pattern silently break the stop path.

3. **Sibling pattern to I334.** Same shape of issue: a bluey stream surface that doesn't follow Dart conventions, forcing every consumer to write the same workaround. The conventions matter most precisely where lifecycle / resource use is concerned.

## Proposed fix

In `bluey/lib/src/discovery/bluey_scanner.dart:117`, attach an `onCancel` callback to the controller that calls `stop()`:

```dart
final controller = StreamController<ScanResult>(
  onCancel: () {
    // Match Dart convention: cancelling the subscription stops the
    // underlying work. Bluey's `stop()` is idempotent (returns early
    // if `!_isScanning`), so this is safe to call even if the scan
    // already finished via timeout or `_finishScan`.
    return stop();
  },
);
_activeScanControllers.add(controller);
```

`stop()` (line 184) already cancels `_platformSubscription`, calls `_platform.stopScan()`, and emits `ScanStoppedEvent`. The `_isScanning` guard makes it idempotent.

### Edge cases

- **Timeout-driven termination.** If `timeout` fires, the inner code at line 162 already calls `stop().then((_) { controller.close(); })`. After that, `controller.close()` will not fire `onCancel` again (close drains then closes; cancellation of a closed/done subscription is a no-op). No double-stop hazard.

- **Multiple `scan()` calls on the same `Scanner` instance.** Each `scan()` builds a fresh controller; canceling one consumer's subscription on its own stream stops the scan for everyone (because there's only one platform scan per `Scanner`). This is the correct behaviour but worth documenting on the `scan()` method.

- **Consumers that explicitly call `scanner.stop()` after cancel.** Idempotent, no harm.

- **Already-completed `_finishScan` path.** Line 174 closes the controller. Cancellation on a closed stream is a no-op in Dart; `onCancel` would not be invoked again. No regression.

## Why medium severity (not high)

- The radio keeps scanning, which **drains battery and chews radio time**, but does not crash the app or corrupt data.
- Workaround is one line of consumer code (call `scanner.stop()` explicitly), and bluey's API already supports it — it's just not the path most consumers will land on first.
- However, the failure mode is silent and easy to ship without noticing in a normal QA pass that doesn't include a battery / RF profiler. That bumps it up from low.

## Notes

- The `Scanner` interface (`bluey/lib/src/discovery/scanner.dart`) keeps `scan()` and `stop()` separate. After this fix they remain separate methods — consumers can still call `stop()` directly if they want imperative control — but cancelling the stream becomes a working substitute.
- Worth auditing the rest of bluey's stream surfaces (`Server.peerConnections`, `Server.disconnections`, `Server.writeRequests`, connection notification streams) for the same anti-pattern. Many of these are owned by long-lived `Server`/`Connection` instances where cancellation semantics are less critical, but the audit will surface any other footguns.
- Filed alongside I334; both are consumer-side patterns the `gossip_bluey` package had to invent to compensate for stream surfaces that don't follow Dart conventions.

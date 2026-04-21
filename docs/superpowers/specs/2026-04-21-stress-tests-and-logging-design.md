# In-App Stress Tests + Library Logging Instrumentation Design

## Problem

Phase 2a shipped real correctness guarantees (per-connection GATT queue, three typed dead-peer signals, fire-and-forget hardening) — but they're hard to verify post-merge:

- **No in-app way to exercise the library under stress.** The Phase 2a contract claims "no `Failed to <op>` errors under concurrent writes" and "≤15s detection on peer death," but the only way to see those properties hold is to write ad-hoc test scripts in the example app each time. Reproducing reported issues from users requires editing the example app's connection screen.
- **Library has essentially no logging.** The investigation that produced the two lifecycle fixes (`PlatformException(notFound)` and `gatt-status-failed`) required hand-adding `[DIAG:lifecycle]` `print` calls, committing them, removing them after root-cause. Future bug reports will hit the same wall: "what was the library doing?" is unanswerable without recompiling.

## Goal

Two distinct deliverables, bundled for efficiency since they touch overlapping flows:

1. **In-app stress test tool** in the example app, accessible from the connection screen (beneath the Disconnect button) when the connected peer hosts the stress test service. Configurable per-test parameters; live counters; failure breakdown by exception type.
2. **Lightweight library logging** via `dart:developer.log` at ~15–20 key points across `bluey/lib/src/`, using 5 named loggers under the `bluey.*` namespace. Visible in devtools, logcat, and Xcode console without any consumer-side setup.

### In scope

- 7 stress tests (burst write, mixed-op concurrency, long-running soak, timeout probe, failure injection, MTU probe, notification throughput)
- Custom GATT service in the example server with a 6-opcode protocol (`echo`, `burstMe`, `delayAck`, `dropNext`, `setPayloadSize`, `reset`)
- New `stress_tests` feature module in the example app, following existing clean-architecture layering
- `dart:developer.log` instrumentation in `bluey` library, no native-side (Kotlin/Swift) logging
- Per-test config form, live counters with exception-type breakdown, latency p50/p95

### Out of scope (deferred)

- **Proper logging framework** (consumer sinks, log levels API, structured events, native log routing, log-viewer UI) — separate spec.
- **CSV export of test results** — devtools captures logs.
- **Saved test presets** — configs reset to defaults each session.
- **History of past runs** — only the last result per test is shown.
- **Automated test that captures `dev.log` output** — log calls are line-of-code level changes; trust they work.

## Architecture

Three cleanly separated areas of work. The library is touched only for logging instrumentation.

```
┌────────────────────────────────────────────────────────────────┐
│ bluey (library) — touched ONLY for logging                      │
│   * dart:developer.log calls at ~15–20 key points               │
│   * 5 named loggers: bluey.{connection,gatt,lifecycle,peer,server}│
│   * No new public API, no new files, no new tests               │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ bluey/example/lib/features/stress_tests/ — NEW feature module   │
│                                                                 │
│   domain/         — StressTest enum, configs, results           │
│   application/    — one Run<TestName> use case per test         │
│   infrastructure/ — StressTestRunner (encodes commands,         │
│                      observes notifications, accumulates stats) │
│   presentation/   — screen, cubit, state, per-test cards        │
│   di/             — feature registration                        │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ bluey/example/lib/features/server/ — touched to host the         │
│ stress service alongside the existing demo service              │
│   * NEW infrastructure/stress_service_handler.dart              │
│   * MODIFIED domain/server_setup.dart to register the service   │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│ bluey/example/lib/shared/stress_protocol.dart — shared between  │
│ stress_tests (client) and server (handler):                     │
│   * Service + characteristic UUIDs                              │
│   * Sealed StressCommand hierarchy (encode/decode)              │
└────────────────────────────────────────────────────────────────┘
```

### DDD notes

- **`StressCommand`** is a sealed Command-pattern hierarchy — `EchoCommand`, `BurstMeCommand`, `DelayAckCommand`, `DropNextCommand`, `SetPayloadSizeCommand`, `ResetCommand`. Each subclass owns its encode/decode. Adding a future opcode = one new subclass + one new server `case`.
- **`StressTestRunner`** is the only client-side surface that touches `BlueyConnection`. Use cases call it; the cubit consumes its result stream. Keeps `BlueyConnection` interaction in one place.
- **`StressServiceHandler`** is the server-side aggregate root for stress-service state (`_lastEcho`, `_dropNextWrite`, `_payloadSize`, `_burstId`, `_abortBurst`). State resets on server start or on receipt of a `reset` command.
- **Library stays ignorant** of stress tests — UUIDs, opcodes, dispatcher all live in `bluey/example/`. Library only gets logging.

### Test isolation

When the user hits Stop on a running test, the cubit cancels its stream subscription. That stops the client from *tallying* further events, but doesn't stop work already in flight: writes already enqueued in Android's GATT queue execute on the wire, server-side flags (`_dropNextWrite`, `_payloadSize`, `_lastEcho`) persist, and an in-progress `burstMe` loop keeps emitting notifications. Without coordination, the next test runs against a contaminated server.

Two-pronged mitigation:

1. **`reset` opcode + reset-on-start.** Every test's first action is to send `ResetCommand` and await the response. The server clears all state and aborts any in-flight `burstMe` loop. The next test starts from a known baseline regardless of how the previous one ended.

2. **Burst-id filtering.** `burstMe` notifications carry a 1-byte burst-id prefix. The client tracks the expected burst-id for the current run; notifications with a different id are stragglers from a previous (cancelled) burst and are silently dropped. Required because we can't prevent the previous burst's notifications from arriving on the wire — only filter them out client-side.

This design accepts that `Stop` is best-effort cleanup. The reliable cleanup happens at the start of the next test. Trade-off: ~50ms overhead per test for the `reset` round-trip; in exchange, no spec-rot from accumulated server state and no flaky cross-test interference.

### Stress Tests button visibility

The button on `ConnectionScreen` is visible only when the connected peer **hosts the stress test service** — not merely when the peer is a bluey peer. The two are distinct:

| Peer state | `isBlueyServer` | Hosts stress service | Button shown |
|---|---|---|---|
| Generic GATT device (non-bluey) | false | no | no |
| Bluey peer running this example app's server | true | yes | **yes** |
| Bluey peer running a different (custom) bluey-based server | true | no | no |

The stress service is example-app scaffolding, not part of the bluey library — any bluey-based app that doesn't register it won't have it. So the only honest visibility test is *"can the button do useful work?"*, which means *"is `StressProtocol.serviceUuid` in `connection.services`?"*.

`ConnectionCubit` already loads services after connect (`loadServices()` at the end of `connect()`). The stress button widget watches the cubit's `state.services` (or equivalent) and renders only when the stress service is present.

**Hide vs disable:** the button is hidden entirely when the service is absent — not greyed out with a tooltip. For a developer-facing example app, an absent button is less clutter than a disabled one and avoids the "why is this greyed out" question that would lead to the same answer.

## Components

### Stress service protocol — `bluey/example/lib/shared/stress_protocol.dart`

Shared between server-side handler and client-side runner.

**Service definition:**
- Service UUID: `b1e7a001-0000-1000-8000-00805f9b34fb` (`b1e7` "bley" prefix matching the lifecycle service; `a000` range = app-level services)
- One characteristic UUID `b1e7a002-...`, properties `read | write | writeWithoutResponse | notify`

**Frame format (writes from client):**
```
byte 0     : opcode
byte 1..   : opcode-specific payload (little-endian for multi-byte ints)
```

**v1 opcodes:**

| Opcode | Name | Payload (from client) | Server behaviour |
|--------|------|-----------------------|------------------|
| `0x01` | `echo` | any bytes | Server stores payload, returns it on next read, fires a notification with it |
| `0x02` | `burstMe` | `uint16 count` (LE), `uint16 payloadSize` (LE) | Server increments its `_burstId` counter, then fires `count` back-to-back notifications. Each notification: `[burstId, ...payload]` where payload is `payloadSize` bytes of deterministic pattern (`[0,1,2,...]`). Loop checks an abort flag between emissions; `reset` sets it. |
| `0x03` | `delayAck` | `uint16 delayMs` (LE) | Server waits `delayMs` ms before responding to the write |
| `0x04` | `dropNext` | none | Server silently ignores the next write (no response, no notification). Self-clears after one drop. |
| `0x05` | `setPayloadSize` | `uint16 sizeBytes` (LE) | Server's next read returns `sizeBytes` bytes of deterministic pattern |
| `0x06` | `reset` | none | Clears `_lastEcho`, sets `_dropNextWrite = false`, resets `_payloadSize = 20`, sets the burst abort flag (interrupts any in-flight `burstMe` loop), responds with success. |

**Sealed Dart-side hierarchy:**
```dart
sealed class StressCommand {
  Uint8List encode();
  static StressCommand decode(Uint8List bytes);
}
class EchoCommand extends StressCommand { final Uint8List payload; ... }
class BurstMeCommand extends StressCommand { final int count; final int payloadSize; ... }
class DelayAckCommand extends StressCommand { final int delayMs; ... }
class DropNextCommand extends StressCommand { ... }
class SetPayloadSizeCommand extends StressCommand { final int sizeBytes; ... }
class ResetCommand extends StressCommand { ... }
```

**Read response (no framing):** the characteristic's read returns either the last `echo`'d value, or — if `setPayloadSize` was the most recent op — `sizeBytes` of pattern.

**Unknown opcode:** server responds with `PlatformGattStatus.requestNotSupported` → reaches client as `GattOperationFailedException` (status non-zero). Validates the new contract path.

### Server-side — `bluey/example/lib/features/server/infrastructure/stress_service_handler.dart`

```dart
class StressServiceHandler {
  Uint8List _lastEcho = Uint8List(0);
  bool _dropNextWrite = false;
  int _payloadSize = 20;
  int _burstId = 0;        // increments per burstMe invocation
  bool _abortBurst = false; // set by reset; checked between notifications

  Future<void> onWrite(WriteRequest req, BlueyServer server) async {
    if (_dropNextWrite) {
      _dropNextWrite = false;
      return; // no response → client times out
    }
    final cmd = StressCommand.decode(req.value);
    switch (cmd) {
      case EchoCommand(:final payload):
        _lastEcho = payload;
        server.respondToWrite(req, status: PlatformGattStatus.success);
        server.notify(req.deviceId, StressProtocol.charUuid, payload);

      case BurstMeCommand(:final count, :final payloadSize):
        _abortBurst = false;
        _burstId = (_burstId + 1) & 0xff;
        final thisBurstId = _burstId;
        server.respondToWrite(req, status: PlatformGattStatus.success);
        for (var i = 0; i < count; i++) {
          if (_abortBurst) break;
          final pattern = _generatePattern(payloadSize);
          // Prepend burst-id so client can filter stragglers from a
          // previous burst that the user cancelled.
          final payload = Uint8List(pattern.length + 1)
            ..[0] = thisBurstId
            ..setRange(1, pattern.length + 1, pattern);
          server.notify(req.deviceId, StressProtocol.charUuid, payload);
        }

      case DelayAckCommand(:final delayMs):
        await Future.delayed(Duration(milliseconds: delayMs));
        server.respondToWrite(req, status: PlatformGattStatus.success);

      case DropNextCommand():
        _dropNextWrite = true;
        server.respondToWrite(req, status: PlatformGattStatus.success);

      case SetPayloadSizeCommand(:final sizeBytes):
        _payloadSize = sizeBytes;
        server.respondToWrite(req, status: PlatformGattStatus.success);

      case ResetCommand():
        _lastEcho = Uint8List(0);
        _dropNextWrite = false;
        _payloadSize = 20;
        _abortBurst = true; // interrupts any in-flight burstMe loop
        server.respondToWrite(req, status: PlatformGattStatus.success);
    }
  }

  Uint8List onRead(ReadRequest req) =>
      _lastEcho.isEmpty ? _generatePattern(_payloadSize) : _lastEcho;
}
```

Server-side state (`_lastEcho`, `_dropNextWrite`, `_payloadSize`, `_burstId`, `_abortBurst`) is per-server-instance, shared across all centrals (matches BLE peripheral semantics — one GATT database per peripheral).

### Client-side — `bluey/example/lib/features/stress_tests/`

**Domain:**
```dart
enum StressTest {
  burstWrite, mixedOps, soak,
  timeoutProbe, failureInjection, mtuProbe, notificationThroughput,
}

sealed class StressTestConfig { const StressTestConfig(); }
class BurstWriteConfig extends StressTestConfig {
  final int count;          // default 50
  final int payloadBytes;   // default 20
  final bool withResponse;  // default true
}
class MixedOpsConfig extends StressTestConfig {
  final int iterations;     // default 10 (each iteration: write+read+discoverServices+requestMtu)
}
class SoakConfig extends StressTestConfig {
  final Duration duration;  // default 5 minutes
  final Duration interval;  // default 1 second
  final int payloadBytes;   // default 20
}
class TimeoutProbeConfig extends StressTestConfig {
  final Duration delayPastTimeout; // default 2s past per-op timeout
}
class FailureInjectionConfig extends StressTestConfig {
  final int writeCount;     // default 10 (including the one being dropped)
}
class MtuProbeConfig extends StressTestConfig {
  final int requestedMtu;   // default 247
  final int payloadBytes;   // default = requestedMtu - 3 (ATT header)
}
class NotificationThroughputConfig extends StressTestConfig {
  final int count;          // default 100
  final int payloadBytes;   // default 20
}

class StressTestResult {
  final int attempted;
  final int succeeded;
  final int failed;
  final Map<String, int> failuresByType;  // exception class name → count
  final Map<int, int> statusCounts;       // for GattOperationFailedException only
  final Duration elapsed;
  final List<Duration> latencies;         // microsecond-precision per-op
  final bool isRunning;

  Duration get medianLatency => ...;
  Duration get p95Latency => ...;
}
```

**Application — one use case per test, e.g.:**
```dart
class RunBurstWrite {
  final StressTestRunner _runner;
  Stream<StressTestResult> call(BurstWriteConfig config, Connection conn);
}
```

**Infrastructure — `StressTestRunner`:**
- Single class encapsulating the BlueyConnection interaction.
- Public methods: `runBurstWrite`, `runMixedOps`, `runSoak`, `runTimeoutProbe`, `runFailureInjection`, `runMtuProbe`, `runNotificationThroughput`.
- Each returns a `Stream<StressTestResult>` that emits incremental snapshots as ops complete.
- Encodes `StressCommand`s, awaits writes, observes notifications, catches exceptions, accumulates counters.
- **Every method begins by sending `ResetCommand` and awaiting the response.** This is the test-isolation contract: regardless of what state the previous test left the server in, the new test starts from a known baseline. The reset call's own success/failure is logged via `bluey.gatt` but does NOT count toward the test's `attempted`/`succeeded`/`failed` totals — it's prologue, not part of the measurement.
- For `runNotificationThroughput`, the runner reads the current burst-id from the server's first notification of the new burst and filters subsequent notifications by it — stragglers from a cancelled previous burst (different burst-id) are dropped.
- Cancellable via the stream subscription. On cancel, the runner stops launching new ops; in-flight ops complete in the background and are not tallied.

**Presentation:**
- `StressTestsScreen` — column of `TestCard` widgets, one per test type
- `StressTestsCubit` — holds current run state per card, dispatches use cases
- `TestCard` — title, run/stop button, inline `ConfigForm`, `ResultsPanel`
- `ConfigForm` — per-test parameter inputs (TextField for ints, Switch for bools, DropdownButton for Duration)
- `ResultsPanel` — counters, exception breakdown, latency p50/p95, elapsed timer

**One-test-at-a-time invariant:** while a card is running, all other cards' Run buttons disable. Keeps stats clean.

**Disconnect handling:** if the connection drops mid-test, the cubit cancels the run, marks the result as terminated by disconnect, and the `StressTestsScreen` pops back to the connection screen.

### Library logging — `bluey/lib/src/`

5 named loggers, ~15–20 `dev.log` calls. Pure additive; no new files, no API changes, no new tests.

| Logger | Files | Events |
|--------|-------|--------|
| `bluey.connection` | `bluey.dart`, `bluey_connection.dart` | connect started/succeeded/failed, state transitions, disconnect called |
| `bluey.gatt` | `bluey_connection.dart` | per-op start/complete (with duration ms) / failure (with exception type + status if applicable), Service Changed received |
| `bluey.lifecycle` | `lifecycle_client.dart` | heartbeat started (interval), heartbeat fail (counter increment), trip → onServerUnreachable (SEVERE) |
| `bluey.peer` | `bluey.dart` _upgradeIfBlueyServer, `bluey_peer.dart` | upgrade attempt, control service discovered y/n, server ID read, upgrade complete |
| `bluey.server` | `gatt_server/bluey_server.dart` | start, service added, advertising started/stopped, central connected/disconnected |

Levels: default (info) for normal events; `Level.WARNING` (900) for recoverable errors; `Level.SEVERE` (1000) for terminal errors.

**Successful per-heartbeat acks deliberately not logged** — every 5s would spam the console. Only failures and the trip event log.

## UI design

### `StressTestsScreen` — single screen, vertical list of test cards

```
┌────────────────────────────────────────────────┐
│ ← Stress Tests                                 │
│ Connected: <peer name>                         │
├────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────┐   │
│ │ Burst Write              [Run]  [Stop]   │   │
│ │ count: [50  ] bytes: [20  ] ☑ withResp   │   │
│ │                                          │   │
│ │ Attempted  50    Succeeded  48  Failed 2 │   │
│ │ Failures:                                │   │
│ │   GattTimeoutException        × 2        │   │
│ │ Median latency: 23ms  p95: 41ms          │   │
│ └──────────────────────────────────────────┘   │
│                                                │
│ … Mixed ops, Soak, Timeout probe, Failure      │
│ injection, MTU probe, Notification throughput …│
└────────────────────────────────────────────────┘
```

**Card states:**
- Idle (no run yet): config form active, Run button enabled, results panel hidden
- Running: config form disabled, Stop button enabled, results panel updating live
- Complete: config form active again, results panel frozen at final values

**Stop behaviour:** cancels the stream subscription, marks result as cancelled, leaves counters at their last values. In-flight ops complete in the background but aren't tallied; server-side state is left dirty. The next test's `reset` prologue cleans it up.

## Data flow — burst write example

```
User taps Run
   │
   ▼
StressTestsCubit.runBurstWrite(config, connection)
   │  validates connection.state == connected
   │  marks card as running
   │  calls RunBurstWrite use case
   ▼
RunBurstWrite.call(config, connection)
   │  delegates to runner
   ▼
StressTestRunner.runBurstWrite(config, connection)
   │  resolves stress service + characteristic from connection.services()
   │  creates Stream<StressTestResult> via StreamController
   │
   │  // PROLOGUE: clean slate
   │  await characteristic.write(ResetCommand().encode(), withResponse: true)
   │
   │  for i in 0..config.count:
   │    final cmd = EchoCommand(payload: pattern(config.payloadBytes))
   │    final start = stopwatch.elapsedMicroseconds
   │    spawn future:
   │      try {
   │        await characteristic.write(cmd.encode(),
   │                                   withResponse: config.withResponse)
   │        record success + latency
   │      } catch (e) {
   │        record failure + exception type + status (if GattOperationFailedException)
   │      }
   │      emit current snapshot to controller
   │
   │  await Future.wait(all futures)  // burst = no awaits between ops
   │  emit final snapshot
   │  close controller
   ▼
Cubit subscribes to the stream → emits StressTestState updates → UI rebuilds
```

## Error handling

Failure modes the runner catches and tallies:

| Mode | Trigger | Classified as |
|------|---------|---------------|
| Timeout | `GattTimeoutException` | `failuresByType['GattTimeoutException']++` |
| Disconnect | `DisconnectedException` | `failuresByType['DisconnectedException']++` ; runner stops further ops; cubit pops screen |
| Status failure | `GattOperationFailedException(status)` | `failuresByType['GattOperationFailedException']++` AND `statusCounts[status]++` |
| Other `BlueyException` | any | `failuresByType[exception.runtimeType.toString()]++` |
| Unexpected (non-`BlueyException`) | any | logged via `bluey.gatt` SEVERE; counted as `failuresByType['Unknown']++` |

**Mid-test disconnect:** the runner detects via the connection state stream (subscribed in parallel with op execution); on disconnected, it cancels pending ops, emits a final snapshot with `isRunning=false`, and signals termination. The cubit pops the stress tests screen back to the connection screen.

**Connection lost before screen opens:** screen shows a "Connect a device first" empty state.

## Testing

### Stress tests feature

- **Shared protocol:** unit tests for `StressCommand.encode/decode` round-trips for each opcode (in `bluey/example/test/shared/stress_protocol_test.dart`).
- **Domain:** unit tests for `StressTestResult` aggregation (median/p95 calculation, counter accumulation).
- **Application:** unit tests for each use case using a fake `StressTestRunner` that emits canned result sequences.
- **Infrastructure:** integration test for `StressTestRunner.runBurstWrite` using `FakeBlueyPlatform`. Exercises: success path, timeout path (via `simulateWriteTimeout`), status-failed path (via `simulateWriteStatusFailed`), disconnect mid-burst (via `simulateWriteDisconnected`).
- **Presentation:** widget tests for `TestCard` state transitions (idle → running → complete; results panel appearance).

### Server-side stress service handler

- Unit tests for `StressServiceHandler.onWrite` for each opcode, asserting state mutation and (mocked) `BlueyServer.respondToWrite` / `notify` calls.
- Specifically test `dropNext` self-clears after one drop.
- Specifically test unknown opcode → response with `PlatformGattStatus.requestNotSupported`.
- Specifically test `reset` clears all state (`_lastEcho` empty, `_dropNextWrite=false`, `_payloadSize=20`) and sets the burst abort flag.
- Specifically test that a `reset` mid-`burstMe` interrupts the notification loop (verify only the notifications emitted before the abort flag was checked are sent).
- Specifically test `burstMe` increments `_burstId` and prepends the new id to every notification's payload.

### Library logging

- **No dedicated tests.** Log calls are line-of-code level changes; manual verification via running the example app and checking devtools/logcat.
- If a log point regresses (e.g. is silently removed), the next stress test run will surface it via missing entries.

## Migration plan

TDD-first commit order. Each commit leaves the workspace green.

1. `feat(example): add stress test protocol shared module` — RED + GREEN. New `bluey/example/lib/shared/stress_protocol.dart`. Sealed `StressCommand` hierarchy (6 subclasses) with `encode`/`decode` per opcode. Tests in `bluey/example/test/shared/stress_protocol_test.dart` cover round-trips.

2. `feat(example): add stress service handler in server feature` — RED + GREEN. New `infrastructure/stress_service_handler.dart`. Tests for each opcode's behaviour (echo, burstMe with burst-id prefix, delayAck, dropNext, setPayloadSize, reset, unknown). Includes the burst-abort-on-reset test. Wires into `server_setup.dart` so the example server registers the stress service alongside the demo service.

3. `feat(example): scaffold stress_tests feature module` — empty domain types, use case stubs, runner skeleton, cubit + state, screen with empty test cards. No real logic yet. Wired into navigation: `ConnectionScreen` gains a "Stress Tests" button immediately beneath the existing Disconnect button (same `GestureDetector` + `Container` style for visual consistency). See "Stress Tests button visibility" in Architecture for the visibility rule.

4. `feat(example): implement StressTestRunner.runBurstWrite + RunBurstWrite use case` — RED + GREEN. Integration tests using `FakeBlueyPlatform` for success/timeout/status-failed/disconnect paths.

5. `feat(example): wire BurstWrite card to runner + result display` — config form, run/stop, results panel. Widget tests for state transitions.

6. `feat(example): implement remaining 6 tests` — one commit per test (`runMixedOps`, `runSoak`, `runTimeoutProbe`, `runFailureInjection`, `runMtuProbe`, `runNotificationThroughput`) with use case + card UI + tests. Six commits total.

7. `chore(bluey): instrument library with dart:developer.log` — single commit. All ~15–20 log points across 5 named loggers. No tests.

8. `docs(bluey): document logger names and stress tests` — README/docs additions explaining how to filter logs in devtools/logcat and how to use the stress tests screen.

Order rationale: protocol first (shared between client and server), server next (so client has something real to talk to), then client feature scaffolding and tests in order of complexity. Logging last — pure additive change with no dependencies.

## Success criteria

- All 7 stress tests run end-to-end against an example bluey peer (iOS↔Android both directions).
- Each test's failure breakdown correctly categorises `GattTimeoutException`, `DisconnectedException`, `GattOperationFailedException(status)`.
- `flutter analyze` clean across the workspace.
- All Dart + Kotlin unit/integration tests pass.
- Manual verification: `Timeout probe` triggers a `GattTimeoutException` with the expected operation name and within `delayPastTimeout` of the per-op timeout.
- Manual verification: `Failure injection` triggers timeout (no ack from dropped write), then subsequent ops succeed (queue drained correctly).
- Manual verification: `Notification throughput` receives all `count` notifications with intact pattern bytes.
- Manual verification: stopping a test mid-run and immediately starting a different test produces clean results — no stale notifications, no `dropNext` leak from the cancelled run, no `setPayloadSize` leak.
- Library log output visible in devtools when running the example app: `bluey.connection`, `bluey.gatt`, `bluey.lifecycle`, `bluey.peer`, `bluey.server` namespaces all appear during normal use.

## Open questions

None at design time. All scoping decisions settled above.

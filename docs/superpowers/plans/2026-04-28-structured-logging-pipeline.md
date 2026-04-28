# Plan — Structured logging pipeline (I307)

**Branch:** `feat/structured-logging` (worktree at `.worktrees/structured-logging/`)
**Backlog:** [I307](../../backlog/I307-structured-logging-pipeline.md)
**Target version:** 0.3.0 across all four packages.
**Discipline:** TDD (Red → Green → Refactor); subagent-driven dispatch where helpful.

## Goal

Add a single, ordered, structured log stream from the Bluey domain layer through both Android and iOS native code. Consumers configure a level and listen — every internal log event flows through one stream regardless of which side of the platform channel emits it.

```dart
final bluey = Bluey();
bluey.setLogLevel(BlueyLogLevel.debug);
bluey.logEvents.listen((e) {
  print('${e.timestamp.toIso8601String()} '
        '[${e.level.name}] ${e.context}: ${e.message} ${e.data}');
});
```

## Decisions (locked in pre-plan)

1. **Stream API**, not callback. Broadcast `Stream<BlueyLogEvent>` exposed as `Bluey.logEvents`.
2. **Free-text + structured fields.** `BlueyLogEvent { timestamp, level, context, message, data, errorCode }`. No sealed-class hierarchy.
3. **Native bridging from day one.** Pigeon `LogEventDto` flows from native → Dart. Filter level set Dart-side and pushed down to native via `setLogLevel` host API; native side checks before marshaling to save Pigeon-call cost.
4. **Aggressive replacement.** Every `dev.log`, `Log.d/i/w/e`, `NSLog`, `print` (in library packages — not the example app) is replaced with a `BlueyLog` call. No coexisting transition period.
5. **Scope of emitters:** Pigeon-call entry/exit (trace), state transitions (info), op-queue events (debug), Service Changed and stale-handle events (warn), heartbeat / lifecycle activity (debug), errors with typed exception (error), advertising start/stop (info), subscription add/remove (debug). The more the merrier.
6. **Default level:** `info`.
7. **TDD.** Tests first.

## Architecture

### Dart-side

```dart
enum BlueyLogLevel { trace, debug, info, warn, error }

class BlueyLogEvent {
  final DateTime timestamp;
  final BlueyLogLevel level;
  final String context;          // e.g. "bluey.connection", "bluey.server.lifecycle"
  final String message;
  final Map<String, Object?> data;
  final String? errorCode;       // present on error events
  // equality by value
}
```

Internal `BlueyLogger`:
- Holds a `StreamController<BlueyLogEvent>.broadcast()`.
- Holds a `BlueyLogLevel _minLevel = BlueyLogLevel.info`.
- `void log(BlueyLogLevel level, String context, String message, {Map<String, Object?> data = const {}, String? errorCode})` — short-circuits if `level.index < _minLevel.index`.
- `void setLevel(BlueyLogLevel level)` — pushes through `_platform.setLogLevel(level)` so native sides also filter.
- `Stream<BlueyLogEvent> get events => _controller.stream`.

`Bluey` exposes:
- `Stream<BlueyLogEvent> get logEvents` → forwards `_logger.events`.
- `void setLogLevel(BlueyLogLevel level)` → forwards `_logger.setLevel(level)`.

`BlueyLogger` is constructed in `Bluey()` and passed (or made accessible via a global accessor) to `BlueyConnection`, `BlueyServer`, `LifecycleClient`, `LifecycleServer`, `BlueyPeer`, `PeerDiscovery`, etc. — anywhere that currently calls `dev.log`.

### Native bridging

**Pigeon (both platforms):**
```dart
enum LogLevelDto { trace, debug, info, warn, error }

class LogEventDto {
  String context;
  LogLevelDto level;
  String message;
  Map<String?, Object?> data;
  String? errorCode;
  int timestampMicros;  // wire-friendly form of DateTime
}

@HostApi()
abstract class BlueyHostApi {
  // ...existing methods...
  void setLogLevel(LogLevelDto level);
}

@FlutterApi()
abstract class BlueyFlutterApi {
  // ...existing callbacks...
  void onLog(LogEventDto event);
}
```

**Android:** a `BlueyLog` Kotlin object:
```kotlin
object BlueyLog {
  @Volatile private var minLevel: LogLevelDto = LogLevelDto.INFO
  @Volatile private var flutterApi: BlueyFlutterApi? = null

  fun bind(api: BlueyFlutterApi) { flutterApi = api }
  fun setLevel(level: LogLevelDto) { minLevel = level }

  fun log(level: LogLevelDto, context: String, message: String,
          data: Map<String, Any?> = emptyMap(), errorCode: String? = null) {
    if (level.ordinal < minLevel.ordinal) return
    // Tee to Android logcat
    when (level) {
      LogLevelDto.TRACE, LogLevelDto.DEBUG -> Log.d(context, message)
      LogLevelDto.INFO  -> Log.i(context, message)
      LogLevelDto.WARN  -> Log.w(context, message)
      LogLevelDto.ERROR -> Log.e(context, message)
    }
    // Bridge to Dart
    flutterApi?.onLog(LogEventDto(
      level = level, context = context, message = message,
      data = data, errorCode = errorCode,
      timestampMicros = nowMicros(),
    )) {}
  }
}
```

Replace every `Log.d("ConnectionManager", "...")` with `BlueyLog.log(LogLevelDto.DEBUG, "bluey.android.connection", "...")` (or appropriate context/level).

**iOS:** a `BlueyLog` Swift namespace with the same shape. Tees to `os_log` (preferred over `NSLog`) and forwards via `flutterApi.onLog`. iOS currently has no `NSLog`/`print` calls in the library code — Phase B is mostly *adding* logs at meaningful points (CB callbacks, op enqueue, addService, etc.).

### Stream merging

`Bluey._logger`'s controller receives events from two sources:

1. Direct `log(...)` calls from Dart-side code.
2. Native log events arriving via `_flutterApi.onLog(LogEventDto)` → translated to `BlueyLogEvent` and pushed to the same controller.

Resulting `Stream<BlueyLogEvent>` emits events in the order they arrive at the controller. Native events have a `timestampMicros` from the native side, but native and Dart events share the same controller (no separate ordering).

### Bootstrap log loss (accepted limitation)

Broadcast streams drop events with no listener. Logs emitted during `Bluey()` construction (before the consumer subscribes) are lost. Document this — initialization-time logs aren't load-bearing; consumers wanting them can subscribe before the first non-trivial operation.

### Performance

- **Native-side level filter** is checked before constructing the `LogEventDto` and before the Pigeon call. When level is `info`, no `trace`/`debug` events touch the platform channel.
- **Dart-side level filter** is checked before adding to the broadcast controller. When level is `info`, no `trace`/`debug` Dart events allocate a `BlueyLogEvent`.
- Eager message construction (no lazy closures). If a profile shows it matters, we can add `logLazy(level, context, () => message)` later.

## File structure (new files)

```
bluey/lib/src/log/
  log_level.dart            # enum BlueyLogLevel
  log_event.dart            # class BlueyLogEvent (value object)
  bluey_logger.dart         # internal logger; not part of public API

bluey/test/log/
  log_event_test.dart
  log_level_test.dart
  bluey_logger_test.dart

bluey_platform_interface/lib/src/
  platform_log_event.dart   # PlatformLogEvent + PlatformLogLevel
                            # (mirrors Pigeon DTO shape; domain-friendly)

bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/
  BlueyLog.kt               # logging singleton

bluey_ios/ios/Classes/
  BlueyLog.swift            # logging namespace
```

`bluey/lib/bluey.dart` (barrel) exports `BlueyLogLevel` and `BlueyLogEvent`.

---

# Phase A — Dart-side foundation

## A.1: BlueyLogLevel enum + ordering test

**Files:**
- New: `bluey/lib/src/log/log_level.dart`
- New: `bluey/test/log/log_level_test.dart`

- [ ] **A.1.1** — Failing test: `BlueyLogLevel.trace.index < BlueyLogLevel.error.index` (verifies semantic ordering matters).
- [ ] **A.1.2** — Define enum: `trace, debug, info, warn, error` (in order).
- [ ] **A.1.3** — Run test → green.
- [ ] **A.1.4** — Commit: `feat(bluey): add BlueyLogLevel enum (I307)`

## A.2: BlueyLogEvent value object

**Files:**
- New: `bluey/lib/src/log/log_event.dart`
- New: `bluey/test/log/log_event_test.dart`

- [ ] **A.2.1** — Failing tests:
  - Constructor stores all fields.
  - Equality by value (same fields → equal).
  - `toString()` is non-empty and includes level + context + message.
- [ ] **A.2.2** — Implement `BlueyLogEvent` with `final` fields, `==`, `hashCode`, `toString`. Use `meta`'s `@immutable`.
- [ ] **A.2.3** — Tests green.
- [ ] **A.2.4** — Commit: `feat(bluey): add BlueyLogEvent value object (I307)`

## A.3: Internal BlueyLogger with level filter

**Files:**
- New: `bluey/lib/src/log/bluey_logger.dart`
- New: `bluey/test/log/bluey_logger_test.dart`

- [ ] **A.3.1** — Failing tests:
  - `logger.events` is a broadcast stream (multiple subscribers receive).
  - `log(info, ...)` emits an event when `minLevel = info`.
  - `log(trace, ...)` does NOT emit when `minLevel = info`.
  - `setLevel(trace)` allows trace events to flow.
  - `dispose()` closes the controller (no further emissions).
- [ ] **A.3.2** — Implement: `_controller` (broadcast), `_minLevel`, `log(level, context, message, {data, errorCode})`, `setLevel`, `events`, `dispose`.
- [ ] **A.3.3** — Tests green.
- [ ] **A.3.4** — Commit: `feat(bluey): add internal BlueyLogger with level filtering (I307)`

## A.4: Wire Bluey.logEvents and Bluey.setLogLevel

**Files:**
- Modify: `bluey/lib/src/bluey.dart`
- Modify: `bluey/lib/bluey.dart` (barrel — export `BlueyLogEvent` and `BlueyLogLevel`)
- Modify: `bluey/test/bluey_test.dart` (or add a new test file).

- [ ] **A.4.1** — Failing test in `bluey_test.dart`: `bluey.setLogLevel(BlueyLogLevel.trace); expect(bluey.logEvents, emitsThrough(predicate(...)))` — emit a trace event from the (yet-to-be-wired) internal logger and assert it reaches the public stream.
- [ ] **A.4.2** — Add `BlueyLogger _logger` field on `Bluey`. Construct in constructor.
- [ ] **A.4.3** — Add `Stream<BlueyLogEvent> get logEvents => _logger.events`.
- [ ] **A.4.4** — Add `void setLogLevel(BlueyLogLevel level) => _logger.setLevel(level)`.
- [ ] **A.4.5** — Dispose the logger in `Bluey.dispose()`.
- [ ] **A.4.6** — Export `BlueyLogEvent`, `BlueyLogLevel` from barrel.
- [ ] **A.4.7** — Tests green.
- [ ] **A.4.8** — Commit: `feat(bluey): expose Bluey.logEvents and setLogLevel (I307)`

## A.5: Pass logger down through internal subsystems

**Rationale:** `BlueyConnection`, `BlueyServer`, `LifecycleClient`, etc. all need access to the logger. Pass via constructor injection (no globals).

**Files:**
- Modify: `bluey/lib/src/connection/bluey_connection.dart` — add `BlueyLogger logger` to relevant constructors.
- Modify: `bluey/lib/src/connection/lifecycle_client.dart`
- Modify: `bluey/lib/src/gatt_server/bluey_server.dart`
- Modify: `bluey/lib/src/gatt_server/lifecycle_server.dart`
- Modify: `bluey/lib/src/peer/bluey_peer.dart`
- Modify: `bluey/lib/src/peer/peer_discovery.dart`
- Modify: `bluey/lib/src/bluey.dart` — pass `_logger` to all constructions.

- [ ] **A.5.1** — Add `BlueyLogger logger` constructor parameter to each subsystem class. Required (not optional) — every internal subsystem MUST log through it.
- [ ] **A.5.2** — Update Bluey to pass `_logger` to every construction.
- [ ] **A.5.3** — Update test fixtures / mocks to pass a fresh logger (or a fake).
- [ ] **A.5.4** — Tests green: `cd bluey && flutter test` → 738 (existing passing count) preserved.
- [ ] **A.5.5** — Commit: `refactor(bluey): inject BlueyLogger through subsystems (I307)`

## A.6: Replace dev.log in Bluey + BlueyConnection

**Files:**
- Modify: `bluey/lib/src/bluey.dart` (~few dev.log calls)
- Modify: `bluey/lib/src/connection/bluey_connection.dart` (multiple)

- [ ] **A.6.1** — For each `dev.log(message, name: 'bluey.X')` call, replace with `_logger.log(BlueyLogLevel.X, 'bluey.X', message)` at the appropriate level. Inferred levels: state transitions = info, op-queue events = debug, errors = error, etc.
- [ ] **A.6.2** — Add log emissions at points that were previously SILENT but should be loud: connect entry/exit, services discovery start/end, disconnect cause.
- [ ] **A.6.3** — Run full `bluey` suite → green. No regressions.
- [ ] **A.6.4** — Commit: `refactor(bluey): replace dev.log with BlueyLogger in Bluey + BlueyConnection (I307)`

## A.7: Replace dev.log in LifecycleClient

**Files:** `bluey/lib/src/connection/lifecycle_client.dart`

- [ ] **A.7.1** — Replace dev.log calls; add new logs for: heartbeat sent, heartbeat-response received, server-unreachable detected, recordActivity skipped, etc.
- [ ] **A.7.2** — Tests green.
- [ ] **A.7.3** — Commit: `refactor(bluey): use BlueyLogger in LifecycleClient (I307)`

## A.8: Replace dev.log in BlueyServer + LifecycleServer

**Files:**
- `bluey/lib/src/gatt_server/bluey_server.dart`
- `bluey/lib/src/gatt_server/lifecycle_server.dart`

- [ ] **A.8.1** — Replace dev.log calls. Add logs for: addService start/end, central connect/disconnect, request-started/ended, lifecycle-protocol heartbeat received, client-gone fired, etc.
- [ ] **A.8.2** — Tests green.
- [ ] **A.8.3** — Commit: `refactor(bluey): use BlueyLogger in BlueyServer + LifecycleServer (I307)`

## A.9: Replace dev.log in BlueyPeer + PeerDiscovery

**Files:**
- `bluey/lib/src/peer/bluey_peer.dart`
- `bluey/lib/src/peer/peer_discovery.dart`

- [ ] **A.9.1** — Replace dev.log calls. Add logs for: peer-probe attempts, probe success/failure, scan filter results.
- [ ] **A.9.2** — Tests green.
- [ ] **A.9.3** — Commit: `refactor(bluey): use BlueyLogger in BlueyPeer + PeerDiscovery (I307)`

## A.10: Integration test — known-flow log sequence

**Files:** `bluey/test/log/log_integration_test.dart`

- [ ] **A.10.1** — Failing test: drive a `bluey.connect(device)` against `FakeBlueyPlatform`. Subscribe to `bluey.logEvents` with `setLogLevel(trace)`. Assert the emitted sequence includes (in order):
  - `bluey: connect entered`
  - `bluey.connection: connect resolved, deviceId=...`
  - `bluey.connection: services discovery started`
  - `bluey.connection: services discovery resolved, count=N`
  - `bluey.connection: disconnect entered`
  - `bluey.connection: disconnected`
- [ ] **A.10.2** — Implement / fix any logger calls so the sequence matches.
- [ ] **A.10.3** — Test green.
- [ ] **A.10.4** — Commit: `test(bluey): integration test for log sequence on connect-disconnect flow (I307)`

## Phase A checkpoint

- [ ] **A.checkpoint.1** — `cd bluey && flutter test` — all green (738 baseline + new log tests).
- [ ] **A.checkpoint.2** — `flutter analyze` clean.
- [ ] **A.checkpoint.3** — Manual smoke: `cd bluey/example && flutter run -d <android>` and observe `bluey.logEvents` printed (consumer wired in `main.dart` for the smoke). Or write a one-off Dart `print(event)` listener in the example temporarily.
- [ ] **A.checkpoint.4** — Pause for user review before Phase B.

---

# Phase B — Native bridging

## B.1: Pigeon — LogEventDto, LogLevelDto, onLog FlutterApi, setLogLevel HostApi

**Files:**
- `bluey_android/pigeons/messages.dart`
- `bluey_ios/pigeons/messages.dart`

- [ ] **B.1.1** — Add `LogLevelDto` enum (trace/debug/info/warn/error).
- [ ] **B.1.2** — Add `LogEventDto { context, level, message, data, errorCode, timestampMicros }`.
- [ ] **B.1.3** — Add `setLogLevel(LogLevelDto)` to the existing HostApi.
- [ ] **B.1.4** — Add `onLog(LogEventDto)` to the existing FlutterApi.
- [ ] **B.1.5** — Same edits on the iOS pigeon file.
- [ ] **B.1.6** — Regenerate bindings:
  ```
  cd bluey_android && dart run pigeon --input pigeons/messages.dart
  cd ../bluey_ios && dart run pigeon --input pigeons/messages.dart
  ```
- [ ] **B.1.7** — `flutter analyze` clean across affected packages.
- [ ] **B.1.8** — Commit: `refactor(pigeons): add LogEventDto + onLog/setLogLevel for unified logging (I307)`

## B.2: Platform interface — log event stream + setLogLevel

**Files:**
- `bluey_platform_interface/lib/src/platform_interface.dart`
- New: `bluey_platform_interface/lib/src/platform_log_event.dart`

- [ ] **B.2.1** — Define `PlatformLogEvent` and `PlatformLogLevel` in `platform_log_event.dart` (mirror DTO shape; domain-friendly).
- [ ] **B.2.2** — Add abstract `Stream<PlatformLogEvent> get logEvents` and `Future<void> setLogLevel(PlatformLogLevel level)` to `BlueyPlatform`.
- [ ] **B.2.3** — Test the abstract additions compile.
- [ ] **B.2.4** — Commit: `feat(bluey_platform_interface): add logEvents stream and setLogLevel (I307)`

## B.3: Android native — BlueyLog object

**Files:**
- New: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyLog.kt`
- Modify: `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt` — bind `BlueyLog` to `flutterApi`; implement `setLogLevel`.
- New: `bluey_android/android/src/test/kotlin/com/neutrinographics/bluey/BlueyLogTest.kt`

- [ ] **B.3.1** — Failing JVM tests:
  - `BlueyLog.log` emits via `flutterApi.onLog` when level is met.
  - `BlueyLog.log` does NOT emit when level is filtered.
  - `BlueyLog.log` tees to logcat at the right Log severity.
  - `setLevel(...)` updates the threshold.
- [ ] **B.3.2** — Implement `BlueyLog` per the architecture sketch above.
- [ ] **B.3.3** — Wire in `BlueyPlugin.onAttachedToEngine`: `BlueyLog.bind(flutterApi)`. Implement `setLogLevel(level)` host method to forward to `BlueyLog`.
- [ ] **B.3.4** — JVM tests green.
- [ ] **B.3.5** — Commit: `feat(bluey_android): add BlueyLog Kotlin singleton with level filter and Pigeon bridge (I307)`

## B.4: Replace Log.d/i/w/e in Android native

**Files:**
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt` (~50+ Log.d calls)
- `bluey_android/android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt` (~15+ Log.d calls)
- Other native Kotlin files as needed.

- [ ] **B.4.1** — Replace `Log.d(TAG, msg)` with `BlueyLog.log(LogLevelDto.DEBUG, "bluey.android.connection", msg)` (or equivalent context). Use `INFO` for state transitions, `WARN` for soft failures, `ERROR` for exceptions, `TRACE` for the noisiest per-byte stuff.
- [ ] **B.4.2** — Add structured `data` where it matters (deviceId, characteristicHandle, etc.). E.g.:
  ```kotlin
  BlueyLog.log(LogLevelDto.INFO, "bluey.android.connection",
    "central connected", mapOf("deviceId" to deviceId))
  ```
- [ ] **B.4.3** — JVM tests green.
- [ ] **B.4.4** — Commit: `refactor(bluey_android): replace Log.d with BlueyLog (I307)`

## B.5: iOS native — BlueyLog Swift namespace

**Files:**
- New: `bluey_ios/ios/Classes/BlueyLog.swift`
- Modify: `bluey_ios/ios/Classes/BlueyIosPlugin.swift` — bind `BlueyLog`; implement `setLogLevel`.
- New: `bluey_ios/example/ios/RunnerTests/BlueyLogTests.swift`

- [ ] **B.5.1** — Failing XCTests:
  - `BlueyLog.log` emits via `flutterApi.onLog` when level is met.
  - `BlueyLog.log` does NOT emit when level is filtered.
  - `BlueyLog.log` tees to `os_log` at the right log type.
- [ ] **B.5.2** — Implement `BlueyLog` per the architecture sketch.
- [ ] **B.5.3** — Wire in `BlueyIosPlugin.register`: `BlueyLog.shared.bind(flutterApi)`. Implement `setLogLevel(level)` host method.
- [ ] **B.5.4** — XCTests green via `xcodebuild test ... iPhone 17`.
- [ ] **B.5.5** — Commit: `feat(bluey_ios): add BlueyLog Swift namespace with level filter and Pigeon bridge (I307)`

## B.6: Add iOS native logs at meaningful points

**Rationale:** Today iOS has zero `NSLog`/`print` in library code. Phase B.6 adds logs at every point the Android side currently does — closing the observability gap.

**Files:**
- `bluey_ios/ios/Classes/CentralManagerImpl.swift`
- `bluey_ios/ios/Classes/PeripheralManagerImpl.swift`
- `bluey_ios/ios/Classes/CentralManagerDelegate.swift`
- `bluey_ios/ios/Classes/PeripheralManagerDelegate.swift`
- `bluey_ios/ios/Classes/PeripheralDelegate.swift`
- `bluey_ios/ios/Classes/OpSlot.swift`

- [ ] **B.6.1** — Audit each Swift file. Add `BlueyLog.log(...)` at:
  - Every CB delegate callback entry (e.g. `centralManager(_:didConnect:)`, `peripheralManager(_:didReceiveRead:)`)
  - Op-slot enqueue / dequeue / timeout
  - addService / didAddService
  - State transitions (`peripheralManagerDidUpdateState`, `centralManagerDidUpdateState`)
  - Errors / failures
- [ ] **B.6.2** — Confirm context names mirror Android (`bluey.ios.central`, `bluey.ios.peripheral`, etc.).
- [ ] **B.6.3** — XCTests still green.
- [ ] **B.6.4** — Commit: `feat(bluey_ios): emit BlueyLog at CB delegate callbacks and op-slot events (I307)`

## B.7: bluey_android Dart shim — wire onLog to platform-interface stream

**Files:**
- `bluey_android/lib/src/bluey_android.dart`
- `bluey_android/lib/src/android_connection_manager.dart` (or wherever `BlueyPlatform`-method-shim lives)

- [ ] **B.7.1** — In the Pigeon callback handler, receive `LogEventDto` → translate to `PlatformLogEvent` → push to a `StreamController<PlatformLogEvent>.broadcast()`.
- [ ] **B.7.2** — Expose as `Stream<PlatformLogEvent> get logEvents`.
- [ ] **B.7.3** — Implement `setLogLevel(PlatformLogLevel)` → call Pigeon host API.
- [ ] **B.7.4** — Tests green.
- [ ] **B.7.5** — Commit: `feat(bluey_android): expose native log stream via platform-interface (I307)`

## B.8: bluey_ios Dart shim — same as B.7 for iOS

**Files:** `bluey_ios/lib/src/bluey_ios.dart` and supporting files.

- [ ] **B.8.1–4** — Mirror B.7 on iOS.
- [ ] **B.8.5** — Commit: `feat(bluey_ios): expose native log stream via platform-interface (I307)`

## B.9: Bluey domain — merge native log stream into unified logEvents

**Files:**
- `bluey/lib/src/bluey.dart`
- `bluey/lib/src/log/bluey_logger.dart`

- [ ] **B.9.1** — In `Bluey()` constructor, subscribe to `_platform.logEvents` and forward each event into `_logger`'s controller (translating `PlatformLogEvent` → `BlueyLogEvent`).
- [ ] **B.9.2** — On `Bluey.setLogLevel(level)`, forward to native via `_platform.setLogLevel(level)` AND to `_logger`.
- [ ] **B.9.3** — Cancel the subscription in `Bluey.dispose()`.
- [ ] **B.9.4** — Test: `FakeBlueyPlatform.emitLog(event)` round-trips through to `bluey.logEvents`. Add `emitLog` helper to `FakeBlueyPlatform` if not present.
- [ ] **B.9.5** — Commit: `feat(bluey): merge native log stream into unified logEvents (I307)`

## B.10: FakeBlueyPlatform supports logEvents + setLogLevel

**Files:** `bluey/test/fakes/fake_platform.dart`

- [ ] **B.10.1** — Add `Stream<PlatformLogEvent> get logEvents` to `FakeBlueyPlatform`. Backed by a `StreamController.broadcast()`.
- [ ] **B.10.2** — Add `void emitLog(PlatformLogEvent event)` for tests to drive native-side events.
- [ ] **B.10.3** — Implement `setLogLevel` (no-op or stash for assertion).
- [ ] **B.10.4** — Tests green.
- [ ] **B.10.5** — Commit: `test(bluey): FakeBlueyPlatform supports log event stream (I307)`

## Phase B checkpoint

- [ ] **B.checkpoint.1** — Full Dart suite green: `bluey`, `bluey_platform_interface`, `bluey_android`, `bluey_ios`.
- [ ] **B.checkpoint.2** — Android JVM tests green.
- [ ] **B.checkpoint.3** — iOS XCTest green (iPhone 17 sim).
- [ ] **B.checkpoint.4** — `flutter analyze` clean.
- [ ] **B.checkpoint.5** — Manual on real devices: connect example app, call `bluey.setLogLevel(BlueyLogLevel.trace)`, listen to `bluey.logEvents`, observe both Dart-side AND native-side events arriving in one stream. Confirm both Android and iOS native events reach the consumer.
- [ ] **B.checkpoint.6** — Pause for user review before Phase C.

---

# Phase C — Cleanup, version bump, close-out

## C.1: Audit residual ad-hoc logging

- [ ] **C.1.1** — Grep for `print(`, `developer.log`, `dev.log`, `Log.d`, `NSLog`, `os_log`, `print(` in library packages (NOT example app). Replace any stragglers.
- [ ] **C.1.2** — Tests still green.
- [ ] **C.1.3** — Commit (only if anything found): `chore: clean up residual ad-hoc logs in library packages (I307)`

## C.2: CLAUDE.md — document logging API

**Files:** `CLAUDE.md`

- [ ] **C.2.1** — Add a "Structured logging" section under Architecture: explain `Bluey.logEvents`, `Bluey.setLogLevel`, the unified-stream contract, the level enum, the `context` naming convention (`bluey.<area>`).
- [ ] **C.2.2** — Update the Ubiquitous Language table if `BlueyLogger` should be canonicalized.
- [ ] **C.2.3** — Commit: `docs(claude): document structured logging API (I307)`

## C.3: README — add logger usage snippet

**Files:** `README.md`

- [ ] **C.3.1** — Add a short snippet showing how to subscribe to `bluey.logEvents` and set a level.
- [ ] **C.3.2** — Commit: `docs(readme): add structured logging snippet (I307)`

## C.4: Bump to 0.3.0 across all four packages

**Files:** `bluey/pubspec.yaml`, `bluey_platform_interface/pubspec.yaml`, `bluey_android/pubspec.yaml`, `bluey_ios/pubspec.yaml`.

- [ ] **C.4.1** — Bump `version: 0.2.0` → `version: 0.3.0`.
- [ ] **C.4.2** — Run `flutter pub get` from worktree root.
- [ ] **C.4.3** — Full suite green.
- [ ] **C.4.4** — Commit: `chore(release): bump to 0.3.0 across all four packages (I307)`

## C.5: CHANGELOG entries

**Files:** four CHANGELOG.md files.

- [ ] **C.5.1** — Add a `## 0.3.0` entry to each:
  - `bluey/CHANGELOG.md` — full description of the new logging API.
  - `bluey_platform_interface/CHANGELOG.md` — `Stream<PlatformLogEvent> get logEvents` + `setLogLevel`.
  - `bluey_android/CHANGELOG.md` — `BlueyLog` Kotlin object; existing `Log.d` calls replaced.
  - `bluey_ios/CHANGELOG.md` — `BlueyLog` Swift namespace; new logs at CB delegate callbacks and op-slot events.
- [ ] **C.5.2** — Commit: `docs(changelog): document I307 structured logging release (I307)`

## C.6: Close I307 in backlog

**Files:**
- `docs/backlog/I307-structured-logging-pipeline.md` — flip frontmatter `status: open` → `status: fixed`, add `fixed_in: <commit-sha>`, append Resolution section.
- `docs/backlog/README.md` — move I307 from Open to Fixed table; cite SHA.

- [ ] **C.6.1** — Edits + commit: `chore(backlog): mark I307 fixed`

## C.7: Final integration sweep

- [ ] **C.7.1** — Full Dart + native suites green.
- [ ] **C.7.2** — `flutter analyze` clean.
- [ ] **C.7.3** — Example app builds Android APK + iOS sim.
- [ ] **C.7.4** — Hand back to user for sign-off. Do NOT push.

## Phase C checkpoint

- [ ] **C.checkpoint.1** — All previous test counts green + new log tests.
- [ ] **C.checkpoint.2** — User reviews and approves the merge.

---

# Branch close-out

- [ ] **F.1** — On user sign-off: `git checkout main && git merge --ff-only feat/structured-logging`.
- [ ] **F.2** — Do NOT `git push` without explicit user instruction.

---

# Risk notes

- **Stream ordering with native bridge.** Native log events arrive on the platform-channel queue. They share the same controller as Dart events, so they're emitted in arrival order — but a "concurrent" pair of Dart-side and native-side events may interleave non-deterministically. Document; don't try to enforce monotonic ordering across the two.
- **Bootstrap log loss.** Broadcast streams drop events with no listener. Logs emitted during `Bluey()` construction are lost. Documented limitation; consumers should subscribe before the first non-trivial operation if they care about init logs.
- **Pigeon-call cost.** Native-side level filter is critical. Verify by profile that level-`info` doesn't ferry trace/debug events over the channel.
- **Test fixture churn.** Many existing tests construct `BlueyConnection`, `BlueyServer`, etc. directly. Adding required `BlueyLogger` to constructors is a wide change. Consider a default `BlueyLogger.silent()` factory so test code that doesn't care about logging can pass it in cheaply. **Decision:** add a `BlueyLogger.silent()` factory that emits to a closed controller (no-op) — keeps test churn down without making the parameter optional in production code.
- **`os_log` vs `NSLog`.** Modern iOS prefers `os_log` (or `Logger` on iOS 14+). For broadest compat in a Flutter plugin targeting iOS 12+, `os_log` is safe. Use it.
- **Don't `--no-verify`.** Per repo conventions, never skip hooks. Worktree-local `commit.gpgsign=false` is fine if 1Password agent fails (matching the rewrite worktree convention) — but only if needed.

---

# End-of-plan checklist

- [ ] Plan committed to `docs/superpowers/plans/`.
- [ ] Phase A green + checkpoint.
- [ ] Phase B green + checkpoint.
- [ ] Phase C green + checkpoint.
- [ ] Backlog I307 closed.
- [ ] Branch merged to main on user sign-off.

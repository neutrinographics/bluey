---
id: I307
title: Add a structured logging pipeline from domain through platform code
category: unimplemented
severity: medium
platform: domain
status: open
last_verified: 2026-04-28
related: [I306]
---

## Symptom

Bluey today emits scattered logs:

- Domain layer: `dev.log(..., name: 'bluey.server')` and similar `dev.log` calls in select files (`bluey_server.dart`, `bluey_connection.dart`, etc.). Log destination is the Flutter `dart:developer` channel (visible in `flutter run` terminal and IDE consoles).
- Android native: `Log.d("ConnectionManager", ...)`, `Log.d("GattServer", ...)` in select call sites. Visible in `adb logcat`.
- iOS native: ad-hoc `NSLog` and `print` (mostly absent — tracing is sparse). Visible in Xcode/Console.app.
- Example app: an in-app `_addLog(category, message)` panel for user-visible events.

These channels don't compose. A consumer of the library can't get a single, ordered, timestamped log stream covering domain ↔ platform-interface ↔ native. Real-device debugging requires watching three different terminals/consoles and manually correlating timestamps. This was the rate-limiting factor when investigating I306 (Android-server + iOS-client disconnect detection).

## Goal

A structured logging pipeline so a consumer can do something like:

```dart
final bluey = Bluey(logger: (e) => print('${e.timestamp} [${e.level}] ${e.context}: ${e.message}'));
```

…and receive a single ordered stream that includes events from:

- Domain layer (`Bluey`, `BlueyServer`, `BlueyConnection`, `LifecycleClient`, `LifecycleServer`, etc.)
- Platform-interface layer (Pigeon-call entry/exit, error translation)
- Native side (Android `ConnectionManager` / `GattServer`; iOS `CentralManagerImpl` / `PeripheralManagerImpl`) — bridged across the platform channel as part of the event stream so logs are ordered with the domain logs.

## Shape

Rough sketch of the API:

```dart
// In domain:
abstract class BlueyLogger {
  void log(BlueyLogEvent event);
}

class BlueyLogEvent {
  final DateTime timestamp;
  final BlueyLogLevel level;        // trace / debug / info / warn / error
  final String context;             // 'bluey.server', 'bluey.connection.discovery', ...
  final String message;
  final Map<String, Object?> data;  // structured fields (deviceId, characteristicHandle, etc.)
  final String? errorCode;          // for error events
}

class Bluey {
  Bluey({BlueyLogger? logger, ...});
}
```

Native side: pipe Android `Log.d` and iOS `NSLog` events for Bluey-internal categories through Pigeon as `LogEventDto`s back to the domain layer. The domain layer interleaves them with Dart-side events and forwards to the configured `BlueyLogger`.

## Why now

The handle-identity rewrite (I088 + I089/I066 + I300 + I301) is feature-complete and shipped at 0.2.0. Real-device manual verification surfaced two distinct edge cases (I305, I306) that were difficult to investigate without a unified log stream. Adding structured logging is the natural next infrastructure step before chasing more BLE corner cases.

## Notes

- Default to a no-op logger — log emission has cost and library consumers shouldn't pay for it unless they opt in.
- Levels matter: `trace` = every Pigeon call entry/exit; `debug` = state transitions, op queue events; `info` = lifecycle milestones (connected, services discovered); `warn` = retries / soft-failures; `error` = exceptions.
- Structured fields > free-text where possible. `deviceId`, `characteristicHandle`, `serviceUuid` should be data fields, not interpolated into messages.
- Native bridging: Pigeon doesn't have a "log event" channel by default. Add a `BlueyLogFlutterApi.onLog(LogEventDto)` Pigeon callback (one direction: native → Dart) that's invoked at the same call sites where native code currently does `Log.d` / `NSLog`. Keep the Pigeon-call cost out of the hot path — gate native log emission behind a `setLogLevel(...)` from Dart.

## Cost-benefit

Medium severity. Not a correctness bug; an infrastructure investment. Pays for itself the first time a consumer hits an integration bug (likely soon — see I306). Estimated 2–4 days of focused work to do well: API design, native bridging, replacing existing scattered logs with the new pipeline, an integration test that asserts a known sequence appears in the log stream.

## Cross-references

- I306 — discovered the need for unified logging during real-device manual verification of the handle rewrite.
- The `dev.log` calls and `Log.d`/`NSLog` ad-hoc tracing scattered across the codebase are the existing "logs" that this pipeline would replace.

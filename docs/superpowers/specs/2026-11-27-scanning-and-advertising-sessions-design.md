# Slice 2: scanning and advertising sessions (design)

Date: 2026-11-27. Status: for Joel's approval. Follows the foundation design (2026-11-17) and slice 1 (link lifecycle, merged in #43, #45 and #46).

## 1. Summary

Slice 2 gives scanning and advertising one owner each, as slice 1 did for links.

- **Scanning.** The radio runs one scan. Every caller (each `scanner.scan()`, and peer discovery) gets a scan of its own on top of it: its own results, filter, timeout and end. The radio scans while any scan is open and stops when the last one leaves. Discovery moves into the target layout (`features/discovery/`, `api/discovery/`), and a scan that the platform refuses reaches the app as a typed failure.
- **Advertising.** One advertising session inside GATT Server owns what is being advertised, the state an app reads and the timeout. A second `startAdvertising` replaces what is advertised. The state always follows what the radio last confirmed.

It closes M2/I013, M4/I336, M5/I382, L1/I386, the Dart half of M8/I385 and I320, and ends the first half of "peer discovery scans through the platform" from slice 1's §6.13.

## 2. Why

Today each of these states has more than one owner, or none.

| Finding | What happens today | Source |
|---|---|---|
| M2 / I013 | `AndroidScanner.scan` and `IosScanner.scan` do not await `startScan`, so a rejected start is an unhandled async error. Android's `onScanFailed(errorCode)` calls `onScanComplete`, which Dart ignores, so the code is dropped and the app's scan stream simply stays silent | `bluey_android/lib/src/android_scanner.dart`, `Scanner.kt` |
| M4 / I336 | `BlueyScanner.stop()` awaits `stopScan` and only then says stopped. A `scan()` made in between starts a platform scan that the pending stop then kills, or leaves the platform scanning while the scanner says stopped | `bluey/lib/src/discovery/bluey_scanner.dart` |
| M5 / I382 | `BlueyScanner.dispose()` never calls `stopScan`, so the radio keeps scanning | same |
| (slice 1 §6.13) | `PeerDiscovery` calls `platform.scan` and `platform.stopScan` itself, so `discoverPeers()` during an app's scan replaces the app's filter and then stops the app's scan | `bluey/lib/src/peer/peer_discovery.dart` |
| L1 / I386 | `startAdvertising` has no guard. A second call while advertising goes to the platform; if it is rejected the state rolls back to `idle` while the radio still advertises, and `stopAdvertising` then does nothing | `bluey/lib/src/gatt_server/bluey_server.dart` |
| M8 / I385 | The advertising timeout is handed to the platform. Android applies it natively in whole seconds and never tells Dart; iOS ignores it. Dart's state says `advertising` after the radio stopped | `Advertiser.kt`, `bluey_server.dart` |
| I320 | The domain builds `scanResponseServiceUuids`, the name of one platform's packet layout | `bluey_server.dart` |

A failed `startAdvertising` also reaches the app as the raw platform error, untranslated, and a failed `stopAdvertising` strands the state at `stopping`.

## 3. Goals, non-goals, anti-goals

**Goals**

1. One state machine for the radio's scan and one for advertising, each pure and synchronous in its context's domain, each the only owner of its state.
2. Discovery placed in the target layout, arriving clean (no entry in any list).
3. Every finding in §2 closed, with its known-defect roster entry struck in the commit that fixes it.
4. Peer discovery scans through Discovery.
5. No list in `known_violations.dart` grows; `bluey_scanner.dart` leaves the lists, `bluey_server.dart` and `events.dart` shrink, and `bluey.dart` does not grow.

**Non-goals**

- Placing the rest of GATT Server or Peer (slice 5). `Server` and `BlueyServer` stay where they are; only advertising moves out of them.
- Splitting `BlueyPlatform` by role and the contract suite over the platforms (slice 3).
- Native completions by identity and the native half of M8 (slice 4). The one native change here is Android reporting its scan failure code.
- Log wording (I399, after slice 6). New lines follow today's wording and contexts.
- De-duplicating results, RSSI smoothing or any new scan feature.

**Anti-goals**

- A scan that ends silently. Every scan ends with a reason, and a failure is never a quiet stream.
- State an app reads that the radio has not confirmed.
- A shared scan that an app can notice: one caller never changes another caller's results, timeout or end.
- A generic "radio session" shared by scanning and advertising. They share a shape, not a rule.

## 4. What Joel decided

1. **One radio scan, a scan per caller** (2026-11-27). Each caller has its own stream, filter and timeout; the radio runs while any is open; peer discovery is one more caller.
2. **A second `startAdvertising` replaces what is advertised** (2026-11-27). If the restart is rejected, the state follows the radio.

Everything else in this document is my call, listed in §11 for him to overrule.

## 5. Approaches considered

**A. A domain aggregate per radio activity, with application sessions over a port (chosen).** The same shape as slice 1's `Link`: a pure aggregate takes inputs and answers events and one duty; an application unit runs the duties over a port, holds the timers and streams, and raises the events; the edge translates. It costs the most files, and it is the only one that gives slice 3 a state machine to run random input sequences over, which the foundation design promises for slices 1 and 2.

**B. Count callers in the application layer, no domain model.** A `SharedScan` class with a reference count, timers and the platform subscription together. Fewer files, and it would fix M4 and M5. It was rejected because the rules that matter (what the radio must scan for when callers differ, what a new ask does while the radio is stopping) would live between `await`s again, which is exactly where M4 came from, and there would be nothing synchronous to test.

**C. One generic radio session for scanning and advertising.** Rejected: scanning is many callers over one radio activity with a union rule; advertising is one owner with a replace rule. A shared abstraction would be parameterised until it held neither rule plainly.

## 6. The design

### 6.1 Language

Discovery (inner):

| Term | Meaning | In code |
|---|---|---|
| Radio scan | The one scan the radio runs for Bluey, and the scans open on it | `RadioScan` (aggregate) |
| Scan | One caller's scan: opened by an ask, open until it ends | `ScanId`, `ScanPhase` |
| Ask | What a caller wants found: a filter and a mode | `ScanAsk`, `ScanFilter`, `ScanMode` |
| Coverage | What the radio must scan for so that every open scan is served | `ScanCoverage` |
| End | Why a scan ended: the caller stopped it, its time ran out, the radio refused, or the radio went away | `ScanEnd` |
| Result | One advertisement heard from one device (the public word, kept) | `ScanResult`, `Device`, `Advertisement` |
| Scanner | One holder of scans, the inner side of a public `Scanner` | `ScannerSession`, `ScannerPhase` |

GATT Server (inner, advertising only):

| Term | Meaning | In code |
|---|---|---|
| Advertising | What this device is advertising and where that stands | `Advertising` (aggregate), `AdvertisingPhase` |
| Content | What is advertised: name, services, manufacturer data, mode | `AdvertisedContent` |
| Supplementary services | Services a scan for them must find, which need not sit in the primary packet | `AdvertisedContent.supplementaryServices` |
| End | Why advertising stopped: asked, timed out, refused, the radio went away | `AdvertisingEnd` |

"Scan response" is spoken only by the adapter (I320).

### 6.2 Where everything lands

```
lib/src/
  shared/
    domain/
      uuid.dart                      moved from shared/uuid.dart
      manufacturer_data.dart         moved from shared/manufacturer_data.dart
      radio_outage.dart              moved from features/connection/domain/link_end.dart
    infrastructure/
      platform_errors.dart           what any platform call can throw, classified once
      radio_outages.dart             the platform's state stream as outages
  features/
    discovery/
      domain/
        device.dart  advertisement.dart  scan_result.dart  scan_mode.dart   (moved)
        scan_filter.dart             ScanFilter: everything, or a set of services
        scan_ask.dart                ScanAsk, ScanCoverage
        scan_id.dart
        scan_phase.dart              ScanPhase, ScanEnd
        scanner_phase.dart           ScannerPhase and the rule that derives it
        radio_scan.dart              the aggregate
        radio_scan_input.dart        its inputs, its step and its duty
        scan_event.dart              ScanEvent family
        scan_failure.dart            ScanFailure family
      application/
        ports/scanning.dart          the radio's scan
        ports/scan_events.dart       where Discovery tells of its scans
        radio_scanner.dart           runs the aggregate's duties, routes results
        scanner_session.dart         one holder's scans and its phase
        open_scan.dart               one scan's results, timer and end
      infrastructure/adapters/
        platform_scanning.dart
        platform_scan_failures.dart
    gatt_server/
      domain/
        advertised_content.dart
        advertise_mode.dart          moved from gatt_server/server.dart
        advertising.dart             the aggregate, its inputs, step and duty
        advertising_phase.dart       AdvertisingPhase, AdvertisingEnd
        advertising_event.dart
        advertising_failure.dart
      application/
        ports/advertiser.dart
        ports/advertising_events.dart
        advertising_session.dart
      infrastructure/adapters/
        platform_advertiser.dart
        platform_advertising_failures.dart
  api/
    discovery/
      scanner.dart                   public Scanner (moved), implemented here
      scan_state.dart                public ScanState (moved)
      scan_state_translation.dart
      scan_events.dart               the five public scan events (moved out of events.dart)
      scan_event_translation.dart    PublishedScanEvents
      scan_failure_translation.dart
      scan_failed_exception.dart     ScanFailedException, ScanFailureReason (new)
      discovery_assembly.dart
    gatt_server/
      advertising_events.dart        the four public advertising events (moved out of events.dart)
      advertising_event_translation.dart
      advertising_state_translation.dart
      advertising_failure_translation.dart
      advertising_assembly.dart
```

`lib/src/discovery/` is deleted. `lib/src/gatt_server/` keeps `server.dart`, `bluey_server.dart`, `advertising_state.dart` (the public enum, which `Server` names) and the rest, until slice 5.

**Into the kernel, against the bar of ARCHITECTURE §4.** `UUID` is an identity every context names. `RadioOutage` is a plain fact with no context's rule, and Connection, Discovery and GATT Server now all end something on it. `ManufacturerData` is a plain measure; it is named by Discovery and GATT Server only, which is one context short of the bar, and I move it anyway because ARCHITECTURE §3 already lists it for the kernel and the alternative is one context importing the other's value (§11, call 9).

### 6.3 Scanning: the aggregate

`RadioScan` holds the radio's phase and the open scans. It is pure: no timers, no streams, no `await`.

Radio phases:

- `Quiet`: the radio is not scanning.
- `Scanning(coverage)`: the radio was asked to scan for `coverage`.
- `Stopping`: a stop is in flight. Exactly one stop is in flight at a time, and the phase is left only when it settles.
- `Unsure`: a stop failed, so the radio may or may not be scanning. No scan is open.

Scan phases: `Waiting` (asked, not yet served), `Scanning`, `Leaving(end)` (it left as the last scan and the radio is stopping because of it; its results have already ended), `Ended(end)`.

A step answers the events raised and at most one duty for the application to run: `Scan(coverage)`, `StopTheRadio` or nothing.

| Input | Radio `Quiet` or `Unsure` | Radio `Scanning(c)` | Radio `Stopping` |
|---|---|---|---|
| `ScanAsked(id, ask)` | the scan is `Waiting`, then at once `Scanning`; radio `Scanning(ask)`; duty `Scan(ask)` | the scan is `Waiting`, then at once `Scanning`. If `c` covers the ask, no duty; otherwise radio `Scanning(c ∪ ask)`, duty `Scan(c ∪ ask)` | the scan is `Waiting`; no duty |
| `ScanLeft(id, end)` | no scan is open: nothing | If others stay: the scan is `Ended(end)`, no duty, coverage kept. If it was the last: the scan is `Leaving(end)`, radio `Stopping`, duty `StopTheRadio` | a `Waiting` scan is `Ended(end)`; nothing else |
| `RadioStopped` | programming error | programming error | each `Leaving(end)` scan is `Ended(end)`. If scans are `Waiting`: they become `Scanning`, radio `Scanning(their union)`, duty `Scan`. Otherwise radio `Quiet` |
| `RadioStopFailed(failure)` | programming error | programming error | each `Leaving(end)` scan is `Ended(end)` with its own end. If scans are `Waiting`: as `RadioStopped`, since a new `Scan` replaces whatever the radio is doing. Otherwise radio `Unsure` |
| `RadioRefused(failure)` | nothing | every open scan is `Ended(EndedByFailure(failure))`; radio `Quiet` | nothing (it describes a scan already being stopped) |
| `RadioWentAway(outage)` | radio `Quiet` | every scan is `Ended(EndedByRadioOutage(outage))`; radio `Quiet` | every scan, `Waiting` and `Leaving`, is `Ended(EndedByRadioOutage(outage))`; the radio stays `Stopping` until the stop settles, then `Quiet` |
| `Closed` (Bluey is disposed) | from `Unsure`: duty `StopTheRadio`, radio `Stopping`. From `Quiet`: nothing | every scan is `Ended(EndedOnRequest)`; radio `Stopping`; duty `StopTheRadio` | every `Waiting` scan is `Ended(EndedOnRequest)`; nothing else |

A stop settles only in `Stopping`, because the application runs exactly one stop per `StopTheRadio` duty and the phase is not left before it settles; anywhere else it is a programming error and the aggregate says so.

The rules behind the table:

- **Every scan passes through `Waiting`.** When the radio is free the same step moves it on to `Scanning`, so a scanner raises "began starting" and then "started" as it does today, and the public state still passes through `starting`.
- **A leaving scan's results end at once**, whatever the radio then does. Only the last leaver waits, as `Leaving`, for the radio's stop, and that is what a public `stopping` shows. Its end is the one it left with; if the stop fails, the caller of `stop()` is told and the failure is logged, and the scan's end does not change.
- **Coverage is the union and only widens while the radio scans.** `ScanFilter` is either everything or a set of services; the union of anything with everything is everything. When a scan leaves and others stay, the coverage is not narrowed, because narrowing is another radio start and Android throttles starts (five in thirty seconds).
- **The mode is the busiest one stated.** A `ScanAsk`'s mode may be absent, which states no preference; the coverage's mode is the busiest among the open scans that stated one, and absent when none did (the platform's default). Peer discovery states none, so it never raises an app's low-power scan.
- **A platform `scan` call replaces the running scan** on both platforms (`Scanner.kt` stops any scan first; CoreBluetooth replaces). So `Scan(coverage)` both starts and widens, and it is also the right thing to do from `Unsure`.
- **The radio gives no confirmation of a start**, on either platform: Android answers only a failure, later, through `onScanFailed`. So a scan is `Scanning` as soon as it is asked while the radio is free, and a refusal arrives as an input that ends the open scans.
- **M4:** an ask while the radio is stopping waits and is started when the stop settles. Nothing is decided between `await`s.
- **M5:** disposing a scanner makes each of its scans leave; the last leaver stops the radio.

**Which scans a result goes to.** `ScanCoverage.wantedBy(result, scans)` decides, purely:

1. A scan whose filter is everything gets every result.
2. A scan with a service filter gets a result that shows one of its services.
3. When the coverage is a set of services and the result shows none of them, the operating system matched it on something Dart cannot see, and every filtered scan gets it. This is not an edge case: iOS matches services held in the overflow area and reports only the services of the primary packet (`CBAdvertisementDataServiceUUIDsKey`), and a backgrounded Bluey server on iOS advertises its control service exactly there. With one filtered scan open, rule 3 is today's behaviour: the OS filter is trusted.

Two limits follow, both stated in §7: with two different service filters open, a result the OS matched invisibly reaches both scans; and while an unfiltered scan is open, the radio scans unfiltered, so iOS reports no overflow matches at all and a filtered scan finds only devices that show the service.

`ScannerPhase` is one holder's standing, derived by one pure rule from its own scans: `scanning` if any is `Scanning`; else `starting` if any is `Waiting`; else `stopping` if any is `Leaving`; else `idle`. Two terminal values sit above the rule: `lost(outage)` once the radio went away, and `closed` once disposed. The radio's phase never enters it: a `Scanner`'s state is about its own scans.

### 6.4 Scanning: application, port and adapter

```dart
abstract interface class Scanning {
  /// Asks the radio to scan for [coverage], replacing what it scans for.
  /// Answers nothing: the radio confirms no start, and a refusal arrives
  /// on [reports].
  void scan(ScanCoverage coverage);

  Future<Either<ScanFailure, void>> stop();

  /// What the radio hears and what it refuses, for one listener. No errors.
  Stream<ScanReport> get reports;      // Heard(ScanResult) | Refused(ScanFailure)

  Stream<RadioOutage> get outages;
}
```

- **`RadioScanner`** (one per `Bluey`) holds the `RadioScan`, feeds it inputs one at a time, runs the duty each step answers over `Scanning`, hands each `Heard` result to the scans the coverage says want it (§6.3), and raises events through `ScanEvents`. It is the only unit that calls the port. Disposing it feeds `Closed`.
- **`OpenScan`** is one scan: its results as a stream that carries no errors, its timeout timer, `leave()`, and `Future<ScanEnd> ended`. The timer makes it leave with `EndedByTimeout`. The platform is never handed `timeoutMs`.
- **`ScannerSession`** (one per `bluey.scanner()`, and one per scan peer discovery makes) opens scans through the `RadioScanner`, keeps its own scans, exposes its `ScannerPhase` and changes, and on disposal makes its scans leave. A `stop()` on it makes every scan of the session leave and answers when the radio stop that caused, if any, has settled, with its failure if it failed.
- **`PlatformScanning`** answers the port over `BlueyPlatform`: it maps `ScanCoverage` to `PlatformScanConfig` (never a timeout), `PlatformDevice` to `ScanResult` (parsing through factories that answer `Either`; a result that does not parse is logged and dropped), and a stream error to `Refused(failure)` through `platform_scan_failures.dart`. It decides nothing.

**Events.** `ScanEvents.raise(ScanEvent)` takes `ScannerBeganStarting`, `ScannerStarted`, `ScannerBeganStopping`, `ScannerStopped(end)`, raised by a `ScannerSession` as its phase changes, and `DeviceHeard(result)`, raised by the `RadioScanner` once per result that at least one open scan gets. Each is stamped by the injected `Now`.

**Failures (I013).** `ScanFailure` is Discovery's sealed family: `ScanRefused(reason)`, `ScanPermissionMissing(permission)`, `ScanRadioUnavailable`, `UnexpectedScanFailure(detail, code, cause)`. `ScanRefusalReason` is `alreadyStarted`, `registrationFailed`, `internalError`, `unsupported`, `outOfHardwareResources`, `startedTooOften`, `unknown`, which are Android's `SCAN_FAILED_*` codes 1 to 6 in Discovery's words.

**The platform seam for I013.**

- `bluey_platform_interface` gains `PlatformScanFailedException(reason, {code})` with `PlatformScanFailureReason`. `scan(config)` keeps its signature; a failed start is an error on the stream it returns, which is what the M2 roster test already demands.
- `AndroidScanner.scan` and `IosScanner.scan` handle the future of `startScan`: a rejection becomes an error on the stream. A rejection of a call that a later `scan` or `stopScan` superseded is dropped, since it describes a scan that is no longer asked for.
- Pigeon (Android) gains `onScanFailed(int errorCode)`; `Scanner.kt`'s `onScanFailed` calls it where it called `onScanComplete`. `AndroidScanner` maps the code and adds the error. This is the slice's only native change, about ten lines of Kotlin; the Gradle tests for it run on Joel's Mac, since they cannot run in the cloud.
- iOS has no asynchronous scan failure. A start while not powered on is already rejected by Swift (`notReady`) and now arrives as `PlatformBluetoothUnavailableException` on the stream.

### 6.5 Scanning: the edge

`api/discovery/` holds the public `Scanner` and its one implementation over a `ScannerSession`.

- `scan({services, timeout, mode})` opens a scan and answers its results. The stream ends when the scan ends; if it ended by failure, the stream first carries the translated exception. Cancelling the subscription makes the scan leave, as today.
- `ScanState` is translated from `ScannerPhase`: `idle → stopped`, `starting`, `scanning`, `stopping`, `lost → invalidated`, `closed → stopped`. After an outage or disposal `scan()` throws `StaleHandleException`, as today.
- `PublishedScanEvents` turns `ScanEvent`s into the five public events, with the same fields and `source` they have today and the instant as `timestamp`.
- `scan_failure_translation.dart` switches over `ScanFailure` with no default: `ScanRefused → ScanFailedException(reason)`, `ScanPermissionMissing → PermissionDeniedException`, `ScanRadioUnavailable → BluetoothUnavailableException`, `UnexpectedScanFailure → BlueyPlatformException`.
- `DiscoveryAssembly` is handed the `Scanning` port, the event publisher, the log and `Now` by the composition root, which alone builds `PlatformScanning` (ARCHITECTURE §3: only the composition root names infrastructure; `ConnectionAssembly` is handed its ports the same way). It builds the `RadioScanner` and `PublishedScanEvents` once per `Bluey`, hands out a `Scanner` per `bluey.scanner()`, answers peer discovery's scan function (§6.6), and is disposed with `Bluey`, which stops the radio if it is still scanning.
- `lib/src/bluey.dart` sits exactly at its 974-line entry. It loses the scanner's construction and gains one assembly, so the wiring is kept to what it replaces; the plan holds the file at or under its count, and anything longer goes into the assembly.

**`ScanFailedException`** is new and public. `BlueyException` is sealed in `shared/exceptions.dart`, a file that sits exactly at its 578-line entry and cannot grow, and a new direct member would break every app's exhaustive `switch`. So `ScanFailedException extends BlueyPlatformException`, declared at `api/discovery/` with its `ScanFailureReason`. An app that matches `BlueyPlatformException` keeps working; an app that wants the reason matches the subclass. This is the one decision in the slice I would most like Joel to look at (§11, call 1).

### 6.6 Peer discovery

`PeerDiscovery` stays unplaced until slice 5, so it may name neither the edge nor another context's code. It is handed, by the composition root, one function whose type it declares itself in kernel words:

```dart
/// Devices heard advertising [service], until the listener cancels.
typedef DevicesAdvertising = Stream<DeviceAddress> Function(UUID service);
```

`DiscoveryAssembly.devicesAdvertising` is that function, and `Bluey` passes it on. Each listen opens a `ScannerSession` of its own with one scan filtered to the service and no stated mode; cancelling makes the scan leave and closes the session; a failure arrives as the translated exception. A session per listen means a Bluetooth toggle does not leave peer discovery with a lost session: the next `discoverPeers()` opens a new one, as it recovers today. `PeerDiscovery` keeps its own window timers, as it has them today, and no longer calls `stopScan`.

What changes: `discoverPeers()` during an app's scan no longer touches the app's filter or stops its scan, and the app's scan no longer starves the probe. `peer_discovery.dart` loses its `frameworkPlacement` entry, since scanning was its only use of the platform. Peer's scans are announced on `bluey.events` like any other scanner's (the same call slice 1 made for probe links).

### 6.7 Advertising: the aggregate

The radio advertises one thing, so there is one `Advertising` per `Bluey`, whichever `Server` object asks. It is pure and holds one phase: `Idle`, `Starting(content)`, `On(content)`, `Stopping(content)`, `Replacing(old, next)`. None is terminal: after an outage it is `Idle` again and a later server can advertise.

| Input | What it does |
|---|---|
| `StartAsked(content)` in `Idle` | `Starting(content)`; duty `Start(content)` |
| `StartAsked(content)` in `On(same content)` | nothing changes on the radio; the step says the ask is already met, so the session only restarts the timeout |
| `StartAsked(next)` in `On(old)` | `Replacing(old, next)`; duty `Stop` |
| `RadioStopped` in `Replacing(old, next)` | `Starting(next)`; duty `Start(next)` |
| `RadioStopFailed(failure)` in `Replacing(old, next)` | `On(old)`: the radio still advertises the old content, and its timeout runs on; the ask fails with `failure` |
| `RadioStarted` in `Starting(content)` | `On(content)` |
| `RadioStartFailed(failure)` in `Starting` | `Idle`, ended by `EndedByFailure(failure)`; the ask fails |
| `StopAsked` or `TimedOut` in `On(content)` | `Stopping(content)`; duty `Stop` |
| `RadioStopped` in `Stopping` | `Idle`, ended by `EndedOnRequest` or `EndedByTimeout` |
| `RadioStopFailed(failure)` in `Stopping(content)` | `On(content)`: the last state the radio confirmed. A stop that was asked fails with `failure`; a timeout's stop is logged at error and not tried again, and the app can still stop |
| `StopAsked` in `Idle` | nothing |
| `RadioWentAway(outage)` in any phase | `Idle`, ended by `EndedByRadioOutage(outage)`; an ask in flight fails |

Replace is stop then start because Android's native `startAdvertising` answers success and does nothing while it is already advertising, so a start alone would not replace anything. A rejected restart therefore leaves the radio quiet and the state `Idle`, which is what "the state follows the radio" means here (decision 2, and L1).

Asks never overlap: the session runs one ask at a time and queues the next, so the aggregate never sees `StartAsked` or `StopAsked` in `Starting`, `Stopping` or `Replacing`. If it does, that is a programming error and it says so. Disposal is not an input: a disposed server asks for a stop, and a disposed `Bluey` does the same once its queue is empty.

### 6.8 Advertising: application, port, adapter and edge

```dart
abstract interface class Advertiser {
  Future<Either<AdvertisingFailure, void>> start(AdvertisedContent content);
  Future<Either<AdvertisingFailure, void>> stop();
  Stream<RadioOutage> get outages;
}
```

- **`AdvertisingSession`** (one per `Bluey`, shared by every `Server` it hands out) holds the `Advertising`, serialises asks, runs duties over `Advertiser`, raises `AdvertisingEvent`s through `AdvertisingEvents`, and owns the timeout: one timer for the content on air, set when the phase reaches `On`, dropped only when the radio confirms that content stopped, which feeds `TimedOut`. The platform is never handed `timeoutMs`, so the timeout behaves the same on both platforms, to the millisecond, and the state follows it (the Dart half of M8).
- **`PlatformAdvertiser`** maps `AdvertisedContent` to `PlatformAdvertiseConfig`. It alone decides that supplementary services go to the scan response, and it leaves out one already listed among the services.
- **`AdvertisingFailure`**: `AdvertisingRefused(reason)` with `dataTooLarge`, `notSupported`, `unknown`; `AdvertisingPermissionMissing`; `AdvertisingRadioUnavailable`; `UnexpectedAdvertisingFailure`.

**The edge and `BlueyServer`.** `Server` and `BlueyServer` are unplaced and may not name the edge, and the public `AdvertisingState` is named by `Server`, so it stays in `gatt_server/advertising_state.dart`. `api/gatt_server/advertising_assembly.dart` is handed the `Advertiser` port by the composition root, builds the one session and the event publisher, and gives each `BlueyServer` three things: the `AdvertisingSession`, an `AdvertisingState Function(AdvertisingPhase)` and a `BlueyException Function(AdvertisingFailure)`. This is the arrangement slice 1 used for `LinkGattClient` and `LinkEnd`.

`BlueyServer.startAdvertising` keeps what is the server's (the capability check, waiting for the control service and pending `addService` calls), builds an `AdvertisedContent` (the control service as a supplementary service when `peerDiscoverable`), asks the session, and throws the translated failure. Its advertising fields, `_setAdvertisingState`, the config mapping and the event emission leave the file. Its own outage and disposal handling stays: a server that saw an outage shows `invalidated` itself, as today, while the session returns to `Idle` on the same outage through its port; a disposed server asks the session to stop, as today's `dispose()` stops the radio.

Two `Server` objects from one `Bluey` therefore share what is advertised: the second one's `startAdvertising` replaces the first one's content under decision 2, and both read the same state. Today the second start is swallowed by Android and the two objects disagree.

Translation: `Idle → idle`, `Starting → starting`, `On → advertising`, `Stopping → stopping`, `Replacing → stopping` while the old content is being stopped (it then passes through `starting`). Failures: `AdvertisingRefused(dataTooLarge) → AdvertisingException(dataTooBig)` and so on over the existing `AdvertisingFailureReason`.

### 6.9 The shared platform-error classification

Slice 1's §11 call 8 left this for the second context that needs it. `shared/infrastructure/platform_errors.dart` declares a sealed `PlatformError` (`PermissionDenied(permission)`, `RadioUnavailable`, `Unexpected(detail, code, cause)`) and `platformErrorOf(Object)`. Each context's adapter first matches the errors that are its own (`PlatformScanFailedException`, `PlatformAdvertiseDataTooLargeException`, the GATT ones), then switches over `PlatformError` with no default into its own failure family. Connection's `connectionFailureFrom` is rewritten onto it in this slice, so there is one classification from the day there are two users. `radio_outages.dart` likewise replaces the copy of the state-stream mapping in `PlatformLinks`.

### 6.10 What stays behind

- `shared/exceptions.dart` and `shared/error_translation.dart` stay unplaced; the edge's translators name them, as Connection's do.
- `events.dart` keeps the events of contexts not yet placed and shrinks by the nine that move.
- `Server`, `BlueyServer`, `AdvertisingState` and the lifecycle server stay in `gatt_server/` for slice 5.
- The example app and the tests change imports only where they named a moved file by path; everything exported from `lib/bluey.dart` keeps its name.

### 6.11 Where contexts still meet, and when each ends

| What still crosses | Where | Ends |
|---|---|---|
| `Bluey` builds peer discovery's scan function from Discovery's edge | `lib/src/bluey.dart` (composition root) | Slice 5: Peer declares a port of its own and a bridge answers it from Discovery |
| GATT Server knows the lifecycle control service to advertise it when `peerDiscoverable` | `bluey_server.dart`, building the content | Slice 5 |
| `BlueyServer` is handed translators by the edge because it sits below it | `api/gatt_server/advertising_assembly.dart` | Slice 5: `Server` moves to `api/gatt_server/` and translates itself |
| `BlueyServer` (to invalidate itself) and the `AdvertisingSession` (to return to idle) each follow radio outages | `bluey_server.dart` | Slice 5: one server session owns the server's end |
| A late Android scan failure cannot be tied to the start that caused it | the Pigeon seam | Slice 4: completion by identity |
| Android still applies no advertising timeout natively, and iOS none | native | Nothing to end: Dart owns the timeout now. Slice 4 removes the unused native parameter |
| `Device` is Discovery's value and `bluey.connect(device)` takes it | `lib/src/bluey.dart` reads `device.address` | Stays: the composition root is where contexts meet |

## 7. What an app can see

Unchanged: every exported name, `Scanner`'s and `Server`'s members, the order of scan and advertising events for a single caller, `invalidated` and `StaleHandleException` after an outage.

Changed, all on purpose:

1. **Two scanners no longer fight.** A second scanner's `scan()` does not replace the first one's filter, and stopping one does not stop the other. `discoverPeers()` no longer disturbs the app's scan.
2. **A refused scan is an error.** The scan's stream carries `ScanFailedException(reason)` and ends, and the state returns to `stopped`. Before, the stream stayed silent.
3. **`ScanFailedException` and `ScanFailureReason`** are new exports (the slice's only additions to `bluey.api`, with the `timestamp` the scan and advertising events now carry from the domain's clock).
4. **A scan's timeout is exact and per scan.** It was handed to the platform as well as timed in Dart.
5. **`dispose()` on a scanner stops the radio** if no other scan is open.
6. **`stop()` then `scan()` without awaiting works**: the new scan delivers results.
7. **A second `startAdvertising` replaces what is advertised.** The state passes `stopping`, `starting`, `advertising`, with the matching events. The same content again changes nothing on the radio and restarts the timeout.
8. **A failed `startAdvertising` throws a `BlueyException`** (`AdvertisingException(dataTooBig)`, `PermissionDeniedException`, ...) where it threw the raw platform error.
9. **A failed `stopAdvertising` leaves the state `advertising`** and throws; it no longer strands `stopping`.
10. **The advertising timeout works on iOS**, is exact on Android, and the state and events follow it.
11. **A wider radio scan than asked.** While two scans with different filters are open, the radio scans for both and does more work than either asked for alone. `DeviceDiscoveredEvent` fires once per result that some open scan got.
12. **Two limits of sharing one radio scan** (§6.3), both from what iOS reports. With two different service filters open, a device the OS matched on a service it does not report reaches both scans. And while any unfiltered scan is open, a filtered scan finds only devices that show the service in their primary packet, so `discoverPeers()` on iOS can miss a backgrounded Bluey server for as long as the app runs an unfiltered scan. Today the same call replaces the app's scan and then stops it. Both go into `bluey/docs/cross-platform-quirks.md`.
13. **Two `Server` objects share advertising** (§6.8).

## 8. Findings closed

| Finding | Closed by |
|---|---|
| M2 / I013 | §6.4: the start's future is handled, the Android code is carried, and the app gets `ScanFailedException` |
| M4 / I336 | §6.3: an ask while stopping waits for the stop |
| M5 / I382 | §6.3 and §6.4: disposal leaves, the last leaver stops the radio |
| Slice 1 §6.13, first half | §6.6 |
| L1 / I386 | §6.7: replace, and the state follows the radio |
| M8 / I385, Dart half | §6.8: the session owns the timeout |
| I320 | §6.1 and §6.8: supplementary services |
| Slice 1 §11 call 8 | §6.9 |

## 9. Delivery

Two pull requests, each green on every gate.

1. **Scanning.** The kernel moves (`UUID`, `ManufacturerData`, `RadioOutage`) and the shared classification first, as mechanical commits; then Discovery's domain, application, adapter and edge; peer discovery through it; the platform seam for I013 (interface, both Dart adapters, Pigeon and the Kotlin callback). Strikes M2, both M4 entries and M5 from the rosters.
2. **Advertising.** GATT Server's advertising domain, session, adapter and edge; `BlueyServer` reduced to asking the session. Strikes L1. Updates `docs/ARCHITECTURE.md`, `CLAUDE.md`'s glossary, the roadmap and the backlog entries.

What needs Joel: his review of each; the Kotlin Gradle test run on his Mac for pull request 1; one device check on Android and one on iOS of two scanners at once, of `discoverPeers()` during a scan, and of an advertising timeout.

## 10. Testing

Test first, as everywhere.

- **Domain.** `RadioScan` and `Advertising` are tested as tables: every input in every phase, including the ones that must do nothing. Coverage rules (`ScanFilter` union, covers and matches; busiest mode) and `ScannerPhase`'s rule are tested as values. The domain floor of 95% holds.
- **Application.** `RadioScanner`, `ScannerSession`, `OpenScan` and `AdvertisingSession` run over `InMemoryScanning` and `InMemoryAdvertiser` in `test/fixtures/features/`, with simulated time for the timeouts, following `docs/testing-conventions.md`.
- **Contract suites.** One per port, run against the in-memory double and against the adapter over `FakeBlueyPlatform`, so the double cannot drift from the adapter.
- **Edge and integration.** The existing scanner and server tests keep passing through `api/`; new ones cover two scanners at once, peer discovery during a scan, a refused scan, replace, a rejected restart and both timeouts.
- **Known defects.** The five roster entries are struck in the commits that fix them, and their tests move into the regular suite.
- **Platform packages.** `bluey_android` and `bluey_ios` Dart tests cover the handled start and the new callback; the fake gains a scan failure by reason.

## 11. Calls I made, for Joel to overrule

1. **`ScanFailedException extends BlueyPlatformException`**, declared at the edge, instead of a new direct member of the sealed `BlueyException`. Non-breaking, and it does not grow a frozen file. The cost is that the family's shape no longer shows scan failure as a sibling of `AdvertisingException`. The alternative is a direct member, which breaks exhaustive switches in apps and needs room made in `exceptions.dart`.
2. **Coverage only widens while the radio scans** and is not narrowed when a scan leaves (§6.3).
3. **The busiest scan mode asked wins.**
4. **A refused radio scan ends every open scan with the failure**, not only the one whose ask caused the start. After a failed widening the radio is quiet on Android, so nobody is being served.
5. **A failed radio stop still ends the scan that left** with its own end (its caller asked for no more results), tells the caller of `stop()` by the failure, and leaves the radio `Unsure`: the next ask scans afresh, and disposal asks it to stop again.
6. **Peer discovery's scans are announced on `bluey.events`** like an app's.
7. **The same advertising content again touches no radio and restarts the timeout.**
8. **A failed stop leaves advertising `advertising`**, the last state the radio confirmed.
9. **`ManufacturerData` moves to the kernel** though only two contexts name it (§6.2).
10. **`Device`, `Advertisement` and `ScanResult` are published from Discovery's domain as they stand**, under the standing rule for values (slice 1 PR 2), although the library, not the app, builds them: they carry no state and have no inner counterpart to translate from.
11. **The scan and advertising events gain the domain's `timestamp`**, as the three connection events did.
12. **`scan(config)` keeps its signature in the platform interface**; a failed start is an error on its stream. Splitting it into a start call and a results stream belongs to slice 3, which splits the interface by role.
13. **Two pull requests**, scanning first.
14. **Which scans get a result the OS matched invisibly:** every filtered scan (§6.3, rule 3), with the two limits of §7 item 12. The alternative, dropping such results once filters differ, would break peer discovery on iOS whenever an app scans for a service of its own.
15. **An absent scan mode states no preference** and never raises another caller's mode.
16. **One advertising session per `Bluey`**, shared by its `Server` objects (§6.8).

Left open on purpose: nothing that changes what gets built. The names in §6.2 may be refined in the plan where the code reads better.

## 12. Design review (cohesion, coupling, DDD, Clean Architecture)

**Single responsibilities.** `RadioScan` decides what the radio must scan for and where each scan stands. `ScannerPhase` derives one holder's standing. `RadioScanner` runs duties and routes results. `OpenScan` is one scan's stream and timer. `ScannerSession` is one holder's scans. `PlatformScanning` maps. `Advertising` decides what is advertised and where it stands. `AdvertisingSession` serialises asks and owns the timeout. `PlatformAdvertiser` maps and alone knows the packet layout. Each edge file translates one thing. No unit holds both a rule and a timer.

**Dependencies and their direction.** Domain files import only `shared/domain`. Application imports its own domain, its ports and `shared/application` (`Now`, the log). Adapters import their ports, `bluey_platform_interface` and `shared/infrastructure`. The edge imports its own context's features and the unplaced public types it must throw or return. Nothing in `features/` names `api/`. `features/discovery` and `features/gatt_server` do not name each other or `features/connection`; the three share only kernel values. The unplaced `BlueyServer` names `features/gatt_server` (its own context) and is handed the edge's translators; the unplaced `PeerDiscovery` names only kernel types.

**Bounded contexts and language.** Scanning is Discovery's and speaks of scans, asks, coverage and results. Advertising is GATT Server's and speaks of content and supplementary services; "scan response" stays in its adapter. Peer reaches scanning through a function in kernel words until it has a port. The two contexts' failure families are separate and sealed.

**Layers.** Every new file's layer is given in §6.2. State machines are in `domain/`, synchronous, with no timers; timers and streams are in `application/`; platform types are in `infrastructure/adapters/`; exceptions and public events are in `api/`.

**Claims checked against source** (at `main` 48cf097):

- `BlueyScanner.stop()` awaits `stopScan` before setting stopped, and `dispose()` does not call `stopScan`: `lib/src/discovery/bluey_scanner.dart`.
- `PeerDiscovery` uses the platform only for `scan` (two call sites) and `stopScan`: `lib/src/peer/peer_discovery.dart` lines 102, 183, 222.
- Only `lib/src/bluey.dart` and `lib/bluey.dart` import files of `lib/src/discovery/`.
- `BlueyServer.startAdvertising` has no state guard, builds `scanResponseServiceUuids`, passes `timeoutMs`, and rethrows the platform's error; `_stopAdvertisingUnguarded` acts only in `advertising` and has no failure path: `lib/src/gatt_server/bluey_server.dart` lines 607 to 714.
- `shared/exceptions.dart` is 578 lines and its `oversized` entry is 578; `BlueyException` is sealed there and `BlueyPlatformException` is a plain class at line 466.
- `RadioOutage` is declared in `features/connection/domain/link_end.dart`, and `PlatformLinks.outages` derives it from `stateStream` (line 85).
- `connectionFailureFrom` maps `PlatformPermissionDeniedException`, `PlatformBluetoothUnavailableException` and `PlatformException` itself: `features/connection/infrastructure/adapters/platform_failures.dart`.
- ARCHITECTURE.md names `Scanning`, `PlatformScanning`, `InMemoryScanning` and `ScanFailure` for this slice, and lists `UUID` and `ManufacturerData` for `shared/domain`.
- The rosters hold M4 (two entries), M5 and L1 in `bluey` and M2 in `bluey_android`.
- `Scanner.kt`'s `onScanFailed` calls `onScanComplete`, its `startScan` stops a running scan first, and `Advertiser.kt` answers success while already advertising (read earlier in this design's research; the plan re-reads both before the tasks that touch them).

**Findings fixed in this document before it was handed over.** A reviewer who read it as its builder found: cells of the scan table that were missing or impossible (a failed stop with nobody waiting, a stop settling after an outage, disposal), now `Unsure`, the rule that `Stopping` is left only when the stop settles, and `Closed` (§6.3); a single caller that would have lost `starting` (§6.3); results filtered in Dart against services iOS does not report (§6.3, rule 3); an advertising session per server over one radio, which would have brought L1 back (§6.7, §6.8); assemblies that built their own adapters, against ARCHITECTURE §3 (§6.5, §6.8); a peer discovery session that an outage would have left lost for good (§6.6); and an absent scan mode ranked as busiest (§6.3). Before that: An earlier draft had the port answer the start as an `Either`; neither platform confirms a start, so the port's `scan` answers nothing and a refusal is a report (§6.4). An earlier draft kept a scanner's `stopping` at the edge; it is now `ScannerPhase`'s, in the domain (§6.3).

Verdict: ready.

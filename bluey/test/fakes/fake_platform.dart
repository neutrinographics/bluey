import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/src/lifecycle.dart';
import 'package:bluey/src/peer/server_id.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;

/// A fake implementation of [BlueyPlatform] for testing.
///
/// This simulates both central and peripheral roles in-memory, allowing
/// integration tests to verify client-server interactions without real
/// Bluetooth hardware.
///
/// ## Usage
///
/// ```dart
/// // Create a fake platform
/// final platform = FakeBlueyPlatform();
///
/// // Simulate a peripheral advertising
/// platform.simulatePeripheral(
///   id: 'device-1',
///   name: 'Test Device',
///   services: [myService],
/// );
///
/// // Now scanning will discover this device
/// final devices = await platform.scan(config).toList();
/// ```
base class FakeBlueyPlatform extends BlueyPlatform {
  /// Creates a fake platform.
  ///
  /// [capabilities] lets tests override the simulated capability matrix,
  /// e.g. to verify that the domain layer respects `canBond=false` /
  /// `canRequestPhy=false` / `canRequestConnectionParameters=false` and
  /// skips the corresponding platform calls (I035 / I065).
  ///
  /// [reportsCentralDisconnects] overrides the `reportsCentralDisconnects`
  /// field of [capabilities] when provided. Pass `false` to simulate an
  /// iOS-like platform where the domain layer must infer disconnections from
  /// lifecycle heartbeat silence (I338). Defaults to the value in
  /// [capabilities] (which is `true` for `Capabilities.fake`), so existing
  /// tests are unaffected.
  FakeBlueyPlatform({
    Capabilities capabilities = Capabilities.fake,
    bool? reportsCentralDisconnects,
  }) : _capabilities =
           reportsCentralDisconnects == null
               ? capabilities
               : Capabilities(
                   platformKind: capabilities.platformKind,
                   canScan: capabilities.canScan,
                   canConnect: capabilities.canConnect,
                   canAdvertise: capabilities.canAdvertise,
                   canRequestMtu: capabilities.canRequestMtu,
                   maxMtu: capabilities.maxMtu,
                   canScanInBackground: capabilities.canScanInBackground,
                   canAdvertiseInBackground:
                       capabilities.canAdvertiseInBackground,
                   canBond: capabilities.canBond,
                   canRequestPhy: capabilities.canRequestPhy,
                   canRequestConnectionParameters:
                       capabilities.canRequestConnectionParameters,
                   canRequestEnable: capabilities.canRequestEnable,
                   canAdvertiseManufacturerData:
                       capabilities.canAdvertiseManufacturerData,
                   reportsCentralDisconnects: reportsCentralDisconnects,
                 ),
       super.impl();

  // === Configuration ===
  BluetoothState _state = BluetoothState.on;
  final Capabilities _capabilities;

  /// Test seam — when true, [setBluetoothState] / [setState] will NOT
  /// push events onto [stateStream] (the cached `_state` is still
  /// updated). Used by [Bluey.create] tests to simulate platforms that
  /// never publish an initial state.
  bool suppressInitialStateEmission = false;

  // === Structured logging (I307) ===
  final StreamController<PlatformLogEvent> _logEventsController =
      StreamController<PlatformLogEvent>.broadcast();
  PlatformLogLevel? _lastSetLogLevel;

  @override
  Stream<PlatformLogEvent> get logEvents => _logEventsController.stream;

  @override
  Future<void> setLogLevel(PlatformLogLevel level) async {
    _lastSetLogLevel = level;
  }

  /// The most recent value passed to [setLogLevel], or `null` if it has
  /// never been called. Test seam for verifying domain-layer wiring.
  PlatformLogLevel? get lastSetLogLevel => _lastSetLogLevel;

  /// Pushes a synthetic native log [event] onto [logEvents]. Test seam
  /// used to simulate native log emission without involving a real
  /// platform implementation.
  void emitLog(PlatformLogEvent event) {
    _logEventsController.add(event);
  }

  // === Simulated Peripherals (devices we can discover/connect to) ===
  //
  // Test fixtures supplied via [simulatePeripheral]. The shape stored
  // here is the *input data* used to populate per-device handle-keyed
  // storage at discovery time. The UUID-keyed `characteristicValues`
  // map is a seed — it is read once during [discoverServices] and
  // written into the per-handle storage on [_DeviceState]. Once
  // discovery has happened, all reads/writes go through handle-keyed
  // storage; the seed map is metadata only.
  final Map<String, _SimulatedPeripheral> _peripherals = {};

  // === Connected Devices (as central) ===
  final Map<String, _ConnectedDevice> _connections = {};

  // === Per-device handle-keyed state ===
  //
  // The fake mirrors the iOS approach: a per-device monotonic counter
  // starting at 1, drawn from a single pool shared by characteristics
  // and descriptors. Handles are minted lazily on the first
  // [discoverServices] call for a device and reused on later calls so
  // they remain stable for the lifetime of the simulated connection.
  // Cleared on [disconnect] / [simulateServiceChange] so a fresh
  // discovery mints fresh handles, matching real-platform behaviour.
  //
  // Handles are minted by tree position, not by attribute UUID — two
  // characteristics with the same UUID under two different services
  // get distinct handles. The handle is the **primary storage key**;
  // UUID is metadata used only for reverse lookup (and only for legacy
  // UUID-only call paths that D.13 will remove entirely).
  final Map<String, _DeviceState> _deviceStates = {};

  // CCCD UUID (Client Characteristic Configuration Descriptor, 0x2902)
  // expanded to the 128-bit form used throughout the test fixtures.
  static const String _cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';

  _DeviceState _stateFor(String deviceId) =>
      _deviceStates.putIfAbsent(deviceId, () => _DeviceState());

  /// Returns the minted handle for [characteristicUuid] on [deviceId],
  /// minting one on the fly if discovery hasn't happened yet. The
  /// peripheral fixture is consulted to walk the service tree so the
  /// minted handle stays consistent with what `discoverServices` would
  /// later emit.
  ///
  /// For duplicate-UUID characteristics this returns the first occurrence
  /// only — tests that need to address a specific instance should obtain
  /// the handle from the discovered services tree instead.
  int? handleFor(String deviceId, String characteristicUuid) {
    final state = _deviceStates[deviceId];
    if (state != null) {
      final handles = state.charHandlesByUuid[characteristicUuid.toLowerCase()];
      if (handles != null && handles.isNotEmpty) return handles.first;
    }
    // Pre-discovery: mint handles for the simulated peripheral's
    // service tree so direct fake calls in tests can address chars
    // by UUID without first requiring `discoverServices`.
    final peripheral = _peripherals[deviceId];
    if (peripheral != null) {
      final s = _stateFor(deviceId);
      _withHandlesAll(s, peripheral);
      final handles = s.charHandlesByUuid[characteristicUuid.toLowerCase()];
      if (handles != null && handles.isNotEmpty) return handles.first;
    }
    return null;
  }

  /// Eagerly mints handles for every characteristic / descriptor in
  /// [peripheral]'s service tree by walking it through the same
  /// minting helpers used by `discoverServices`. Idempotent thanks to
  /// `putIfAbsent` in `_characteristicWithHandle`.
  void _withHandlesAll(_DeviceState state, _SimulatedPeripheral peripheral) {
    for (var sIdx = 0; sIdx < peripheral.services.length; sIdx++) {
      _withHandles(state, peripheral, peripheral.services[sIdx], '$sIdx');
    }
  }

  /// Test-only helper: read by UUID. Resolves [characteristicUuid] to
  /// its minted handle (minting on demand) and forwards to the
  /// handle-keyed [readCharacteristic]. Mirrors the legacy convenience
  /// of the pre-D.13 wire format for integration tests that bypass the
  /// `Bluey` API surface.
  Future<Uint8List> readCharacteristicByUuid(
    String deviceId,
    String characteristicUuid,
  ) {
    final h = handleFor(deviceId, characteristicUuid);
    if (h == null) {
      throw StateError('Characteristic not found: $characteristicUuid');
    }
    return readCharacteristic(deviceId, h);
  }

  /// Test-only helper: write by UUID. See [readCharacteristicByUuid].
  Future<void> writeCharacteristicByUuid(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) {
    final h = handleFor(deviceId, characteristicUuid);
    if (h == null) {
      throw StateError('Characteristic not found: $characteristicUuid');
    }
    return writeCharacteristic(deviceId, h, value, withResponse);
  }

  /// Test-only helper: setNotification by UUID. See
  /// [readCharacteristicByUuid].
  Future<void> setNotificationByUuid(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) {
    final h = handleFor(deviceId, characteristicUuid);
    if (h == null) {
      throw StateError('Characteristic not found: $characteristicUuid');
    }
    return setNotification(deviceId, h, enable);
  }

  /// Test-only helper: notify by UUID. Resolves the local server-side
  /// handle minted at addService time.
  Future<void> notifyCharacteristicByUuid(
    String characteristicUuid,
    Uint8List value,
  ) {
    final h = _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    return notifyCharacteristic(h, value);
  }

  /// Test-only helper: notifyTo by UUID.
  Future<void> notifyCharacteristicToByUuid(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) {
    final h = _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    return notifyCharacteristicTo(centralId, h, value);
  }

  /// Test-only helper: indicate by UUID.
  Future<void> indicateCharacteristicByUuid(
    String characteristicUuid,
    Uint8List value,
  ) {
    final h = _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    return indicateCharacteristic(h, value);
  }

  /// Test-only helper: indicateTo by UUID.
  Future<void> indicateCharacteristicToByUuid(
    String centralId,
    String characteristicUuid,
    Uint8List value,
  ) {
    final h = _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    return indicateCharacteristicTo(centralId, h, value);
  }

  /// Seeds the per-handle backing value for [characteristicHandle] on
  /// [deviceId]. Required for tests that set up duplicate-UUID
  /// characteristics under two services: the legacy
  /// `characteristicValues` map on [simulatePeripheral] is keyed by
  /// UUID and cannot disambiguate two same-UUID chars. Call this after
  /// [Connection.services] has run so the handles exist.
  void setCharacteristicValueByHandle(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
  ) {
    _stateFor(
      deviceId,
    ).charValuesByHandle[characteristicHandle] = Uint8List.fromList(value);
  }

  /// Returns the current per-handle CCCD value for [descriptorHandle]
  /// on [deviceId], or `null` if no CCCD value has been written.
  /// Test-only helper for asserting on the CCCD state after
  /// [setNotification] toggles it.
  Uint8List? cccdValueByHandle(String deviceId, int descriptorHandle) =>
      _deviceStates[deviceId]?.descriptorValuesByHandle[descriptorHandle];

  /// The most recent [PlatformScanConfig] received by [scan]. Public
  /// so tests can assert on the scan filter / timeout chosen by callers
  /// (e.g. peer-discovery's control-UUID filter — see I055).
  PlatformScanConfig? lastScanConfig;

  /// The most recent [PlatformConnectConfig] received by [connect].
  /// Public so tests can assert on the timeout chosen by callers
  /// (e.g. peer-discovery's probe timeout — see I056).
  PlatformConnectConfig? lastConnectConfig;

  // === Server State (as peripheral) ===
  final List<PlatformLocalService> _localServices = [];
  bool _isAdvertising = false;
  PlatformAdvertiseConfig? _advertiseConfig;
  final Map<String, _ConnectedCentral> _connectedCentrals = {};
  int _nextRequestId = 1;

  /// Test-only: centrals the (reused) native manager still "tracks" but the
  /// next-created [BlueyServer] has not heard of. Keyed centralId -> mtu.
  /// Drained by [resetServerSessions] (I338 reset-on-init).
  final Map<String, int> _survivingAnnounced = {};

  /// Module-wide counter for handles minted by [addService] (mirrors
  /// the server-role behaviour on iOS / Android). Starts at 1.
  int _nextLocalHandle = 1;

  /// Maps a local characteristic UUID to the most-recently-minted
  /// handle. Lets [notifyCharacteristic] / [notifyCharacteristicTo]
  /// resolve the handle a real platform would have stamped onto the
  /// inbound CCCD subscriber's request.
  final Map<String, int> _localHandleByCharUuid = {};

  // === Stream Controllers ===
  final _serviceChangesController = StreamController<String>.broadcast();
  final _stateController = StreamController<BluetoothState>.broadcast();
  final _centralConnectionController =
      StreamController<PlatformCentral>.broadcast();
  final _centralDisconnectionController = StreamController<String>.broadcast();
  final _readRequestController =
      StreamController<PlatformReadRequest>.broadcast();
  final _writeRequestController =
      StreamController<PlatformWriteRequest>.broadcast();

  final Map<String, StreamController<PlatformConnectionState>>
  _connectionStateControllers = {};
  final Map<String, StreamController<PlatformNotification>>
  _notificationControllers = {};

  // === Pending Requests (for responding to read/write requests) ===
  final Map<int, Completer<Uint8List>> _pendingReadRequests = {};
  final Map<int, Completer<void>> _pendingWriteRequests = {};

  // === Observed responses (for tests that assert on response args) ===

  /// Records every call to [respondToReadRequest] in order.
  final List<RespondReadCall> respondReadCalls = [];

  /// Test seam: when non-null, the next [respondToReadRequest] call
  /// completes with this error (then resets to null). Lets tests verify
  /// the lifecycle server's catchError path without contriving a real
  /// Pigeon failure.
  Object? respondToReadFailure;

  /// Records every call to [respondToWriteRequest] in order.
  final List<RespondWriteCall> respondWriteCalls = [];

  /// Records every call to [writeCharacteristic] in order.
  final List<WriteCharacteristicCall> writeCharacteristicCalls = [];

  /// Records every call to [readCharacteristic] in order.
  final List<ReadCharacteristicCall> readCharacteristicCalls = [];

  /// Records every call to [setNotification] in order. Carries both the
  /// wire-level handle and the fake-resolved characteristic UUID so tests
  /// can assert on UUID without knowing the per-device handle mapping.
  final List<SetNotificationCall> setNotificationCalls = [];

  /// Records every call to [discoverServices] by deviceId, in order.
  /// Used by tests that need to assert re-discovery happened (e.g. after
  /// a Service Changed event clears the cache).
  final List<String> discoverServicesCalls = [];

  // === Test Helpers ===

  /// When true, writeCharacteristic calls will throw to simulate a dead server.
  bool simulateWriteFailure = false;

  /// When true, writeCharacteristic calls will throw a
  /// [GattOperationTimeoutException] to simulate a remote peer that stopped
  /// acknowledging writes. Distinct from [simulateWriteFailure], which
  /// represents non-timeout errors that should NOT be treated as evidence
  /// of an absent peer.
  bool simulateWriteTimeout = false;

  /// When true, writeCharacteristic calls will throw a
  /// [GattOperationDisconnectedException] to simulate a mid-op link loss
  /// (the platform queue draining a pending op when the GATT connection
  /// drops). Distinct from [simulateWriteTimeout] and [simulateWriteFailure].
  bool simulateWriteDisconnected = false;

  /// When true, setNotification calls will throw a
  /// [GattOperationDisconnectedException] to simulate the CCCD descriptor
  /// write being drained by a mid-op link loss. Used to cover the
  /// fire-and-forget paths in BlueyRemoteCharacteristic (onFirstListen /
  /// onLastCancel) that would otherwise produce unhandled async errors.
  bool simulateSetNotificationDisconnected = false;

  /// When non-null, the next call to [readCharacteristic] consumes
  /// this completer instead of resolving immediately. Consumed (set
  /// to null) as soon as the read call fires, so a subsequent read
  /// falls through to normal handling.
  Completer<Uint8List>? _heldRead;

  /// Once a held read has been consumed by [readCharacteristic], the
  /// completer is parked here so [resolveHeldRead]/[failHeldRead] can
  /// find it. Cleared when resolve or fail is called.
  Completer<Uint8List>? _heldReadInFlight;

  /// Arranges for the next [readCharacteristic] call to be held
  /// indefinitely. Call [resolveHeldRead] or [failHeldRead] to release it.
  void holdNextReadCharacteristic() {
    _heldRead = Completer<Uint8List>();
  }

  /// Resolves the currently-held read future with [value]. Works
  /// whether or not the held read has already been consumed by a
  /// [readCharacteristic] call.
  void resolveHeldRead(Uint8List value) {
    final held = _heldReadInFlight ?? _heldRead;
    if (held == null) {
      throw StateError('No held readCharacteristic to resolve');
    }
    _heldRead = null;
    _heldReadInFlight = null;
    held.complete(value);
  }

  /// Fails the currently-held read future with [error]. Works whether
  /// or not the held read has already been consumed by a
  /// [readCharacteristic] call.
  void failHeldRead(Object error) {
    final held = _heldReadInFlight ?? _heldRead;
    if (held == null) {
      throw StateError('No held readCharacteristic to fail');
    }
    _heldRead = null;
    _heldReadInFlight = null;
    held.completeError(error);
  }

  /// When non-null, the next call to [writeCharacteristic] consumes
  /// this completer instead of resolving immediately. Consumed (set
  /// to null) as soon as the write call fires, so a subsequent write
  /// falls through to normal handling.
  Completer<void>? _heldWrite;

  /// Once a held write has been consumed by [writeCharacteristic], the
  /// completer is parked here so [resolveHeldWrite]/[failHeldWrite]
  /// can find it. Cleared when resolve or fail is called.
  Completer<void>? _heldWriteInFlight;

  /// Arranges for the next [writeCharacteristic] call to be held
  /// indefinitely. Call [resolveHeldWrite] or [failHeldWrite] to release it.
  void holdNextWriteCharacteristic() {
    _heldWrite = Completer<void>();
  }

  /// Resolves the currently-held write future successfully. Works
  /// whether or not the held write has already been consumed by a
  /// [writeCharacteristic] call.
  void resolveHeldWrite() {
    final held = _heldWriteInFlight ?? _heldWrite;
    if (held == null) {
      throw StateError('No held writeCharacteristic to resolve');
    }
    _heldWrite = null;
    _heldWriteInFlight = null;
    held.complete();
  }

  /// Fails the currently-held write future with [error]. Works whether
  /// or not the held write has already been consumed by a
  /// [writeCharacteristic] call.
  void failHeldWrite(Object error) {
    final held = _heldWriteInFlight ?? _heldWrite;
    if (held == null) {
      throw StateError('No held writeCharacteristic to fail');
    }
    _heldWrite = null;
    _heldWriteInFlight = null;
    held.completeError(error);
  }

  /// When non-null, readCharacteristic throws a [PlatformException] with
  /// this [PlatformException.code]. Models platform-layer errors that are
  /// emitted BEFORE reaching the typed-exception translation helper (e.g.
  /// iOS Swift errors with codes not yet mapped by the platform adapter).
  String? simulateReadPlatformErrorCode;

  /// When non-null, readCharacteristic throws a
  /// [GattOperationUnknownPlatformException] carrying this code and an
  /// optional [simulateReadUnknownPlatformExceptionMessage]. Models the
  /// typed exception the iOS adapter emits for `bluey-unknown` errors so
  /// that `_runGattOp`'s translation branch can be exercised in unit tests
  /// without a real platform channel.
  String? simulateReadUnknownPlatformExceptionCode;

  /// Optional message for [simulateReadUnknownPlatformExceptionCode].
  String? simulateReadUnknownPlatformExceptionMessage;

  /// When non-null, writeCharacteristic throws a [PlatformException] with
  /// this [PlatformException.code]. Models platform-layer errors that are
  /// emitted BEFORE reaching the typed-exception translation helper (e.g.
  /// iOS Swift's `BlueyError.notFound` / `.notConnected` when the peer's
  /// GATT handles have been invalidated after an ungraceful disconnect).
  String? simulateWritePlatformErrorCode;

  /// When non-null, writeCharacteristic throws a
  /// [GattOperationStatusFailedException] carrying this GATT status code.
  /// Models Android's `onCharacteristicWrite(status != SUCCESS)` path —
  /// most notably status 0x01 (`GATT_INVALID_HANDLE`) that follows a
  /// peer-side Service Changed event after an iOS server force-kill.
  int? simulateWriteStatusFailed;

  /// When true, the next [writeCharacteristic] call throws synchronously
  /// (before returning a Future). Models a misbehaving non-async platform
  /// impl — `LifecycleClient.start()` must unwind cleanly if this happens.
  /// Auto-clears after one throw.
  bool simulateSyncWriteThrow = false;

  Object? _pendingReadError;

  /// Arranges for the next [readCharacteristic] call to throw [error],
  /// then clears the pending error automatically. Used to inject typed
  /// platform-interface exceptions (e.g. [PlatformPermissionDeniedException])
  /// without needing a dedicated named flag per error type.
  void simulateReadError(Object error) {
    _pendingReadError = error;
  }

  // === Operation latency (audit R3 / NT-2) ===

  /// When non-null, every platform operation waits this long (virtual
  /// time — `Future.delayed` is Timer-backed, so `fakeAsync.elapse`
  /// drives it) before processing. This is what creates genuine
  /// interleaving windows: with the default `null` the fake resolves
  /// ops in microtasks and domain-level operations can never overlap.
  ///
  /// Latency is applied before fault rules and legacy failure flags —
  /// a failure arrives after the simulated round trip, as it would on
  /// a real link. Held operations (`holdNext*`) are consumed first;
  /// they model indefinite in-flight ops and need no extra delay.
  ///
  /// Tests that set this should run under `fakeAsync`; in real-time
  /// tests it would sleep the wall clock.
  Duration? operationLatency;

  // === Fault-rule queue (audit R2 / NT-5) ===
  //
  // The general fault-injection mechanism: scripted, ordered rules with
  // per-device / per-characteristic targeting and bounded repetition.
  // The single-purpose seams in this file (`simulateWrite*`,
  // `simulateConnectFailure`, ...) remain as sugar for the common
  // one-liner cases; anything they can express, a rule can too.

  final List<_FaultRule> _faultRules = [];

  /// Enqueues a fault rule: the next [times] calls to [op] that match
  /// [deviceId] / [characteristicUuid] (null = match any) throw [error],
  /// then the rule retires. Pass `times: null` for a rule that persists
  /// until [clearFaults].
  ///
  /// Rules are consulted in FIFO order; the first match fires. Enqueue a
  /// timeout rule then a status rule to script "first attempt times out,
  /// second is rejected, third succeeds" — the flaky-link shape no
  /// boolean seam can express.
  void enqueueFault(
    FakeOp op,
    Object error, {
    String? deviceId,
    String? characteristicUuid,
    int? times = 1,
  }) {
    assert(times == null || times > 0, 'times must be null or positive');
    _faultRules.add(
      _FaultRule(
        op: op,
        deviceId: deviceId,
        characteristicUuid: characteristicUuid?.toLowerCase(),
        error: error,
        remaining: times,
      ),
    );
  }

  /// Removes every pending fault rule.
  void clearFaults() {
    _faultRules.clear();
  }

  /// Fires the first matching rule for [op], if any: decrements its
  /// budget, retires it at zero, and throws its error.
  void _applyFaultRules(
    FakeOp op, {
    String? deviceId,
    String? characteristicUuid,
  }) {
    for (final rule in _faultRules) {
      if (rule.op != op) continue;
      if (rule.deviceId != null && rule.deviceId != deviceId) continue;
      if (rule.characteristicUuid != null &&
          rule.characteristicUuid != characteristicUuid?.toLowerCase()) {
        continue;
      }
      final remaining = rule.remaining;
      if (remaining != null) {
        rule.remaining = remaining - 1;
        if (rule.remaining == 0) {
          _faultRules.remove(rule);
        }
      }
      // ignore: only_throw_errors
      throw rule.error;
    }
  }

  // === Dual-role virtual link (audit R4 / NT-6) ===
  //
  // Set by [FakeBleLink]. `_outboundLink` is non-null on the fake whose
  // Bluey instance acts as the GATT *client* over the link;
  // `_inboundLink` on the fake whose Bluey instance acts as the *server*.

  FakeBleLink? _outboundLink;
  FakeBleLink? _inboundLink;

  /// Delivers a server-side notify/indicate to the linked central's
  /// client-side notification stream, if [centralId] is the linked one.
  void _deliverLinkedNotification(
    String centralId,
    String charUuid,
    Uint8List value,
  ) {
    final link = _inboundLink;
    if (link != null && link.centralId == centralId) {
      link.central.simulateNotification(
        deviceId: link.deviceId,
        characteristicUuid: charUuid,
        value: value,
      );
    }
  }

  // === Server-side request blackhole (audit R12 / I347) ===

  final Set<String> _blackholedCentrals = {};

  /// While enabled for [centralId], inbound server-bound requests from
  /// that central vanish at the simulated stack: no read/write request
  /// reaches the server role, no response ever returns, and the
  /// sender's future fails with [GattOperationTimeoutException] after
  /// the per-op timeout (10 s, Timer-based — drive with fakeAsync).
  /// This is the fingerprint of the Android role-reversal ATT
  /// blackhole recorded in I208 / cross-platform-quirks.md.
  void simulateServerRequestBlackhole(String centralId, {bool enabled = true}) {
    if (enabled) {
      _blackholedCentrals.add(centralId);
    } else {
      _blackholedCentrals.remove(centralId);
    }
  }

  /// Parks a blackholed request: hangs until the sender-side per-op
  /// timeout fires.
  Future<T> _blackholeRequest<T>(String operation) {
    final completer = Completer<T>();
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError(GattOperationTimeoutException(operation));
      }
    });
    return completer.future;
  }

  // === Write-without-response backpressure (audit R9 / NT-10) ===

  final Map<String, int> _wwrBudgets = {};
  final Map<String, List<Completer<void>>> _parkedWrites = {};

  /// Models a saturated native write-without-response queue for
  /// [deviceId]: the next [budget] WWR writes complete immediately;
  /// writes beyond that park (their futures stay pending, like iOS
  /// gating on `canSendWriteWithoutResponse` — I339) until
  /// [drainPendingWrites] releases them or the link drops (which fails
  /// them with [GattOperationDisconnectedException]).
  void setWriteWithoutResponseBudget(String deviceId, int budget) {
    _wwrBudgets[deviceId] = budget;
  }

  /// Number of parked (in-flight, un-acked) WWR writes for [deviceId].
  int pendingWriteCount(String deviceId) =>
      _parkedWrites[deviceId]?.length ?? 0;

  /// Completes up to [count] parked WWR writes for [deviceId] in FIFO
  /// order (all of them when [count] is null) — the fake's equivalent
  /// of the native ready-to-send drain.
  void drainPendingWrites(String deviceId, {int? count}) {
    final parked = _parkedWrites[deviceId];
    if (parked == null) return;
    final n = count == null ? parked.length : count.clamp(0, parked.length);
    for (var i = 0; i < n; i++) {
      parked.removeAt(0).complete();
    }
  }

  /// Fails every parked WWR write for [deviceId] — called on transport
  /// loss so saturated writers see the link drop (I315 shape).
  void _failParkedWrites(String deviceId) {
    final parked = _parkedWrites.remove(deviceId);
    if (parked == null) return;
    for (final completer in parked) {
      completer.completeError(
        const GattOperationDisconnectedException('writeCharacteristic'),
      );
    }
  }

  // === MTU negotiation + scan failure seams (audit R7 / NT-7, NT-8) ===

  final Map<String, int> _mtuNegotiationCaps = {};

  /// Models a peer/platform that negotiates MTU *down*: [requestMtu]
  /// for [deviceId] grants at most [cap] regardless of what the caller
  /// asks for. Persistent for the fake's lifetime (a peer's cap doesn't
  /// change between requests).
  void simulateMtuNegotiationCap(String deviceId, int cap) {
    _mtuNegotiationCaps[deviceId] = cap;
  }

  Object? _pendingScanFailure;

  /// Arranges for the next [scan] call to emit [error] on its stream
  /// (instead of results) and close — the shape of a native scan
  /// failure (e.g. Android SCAN_FAILED_*; the fake side of I013). Then
  /// clears automatically: a retry scans normally.
  void simulateScanFailure(Object error) {
    _pendingScanFailure = error;
  }

  // === Connect-phase failure seams (audit R1 / NT-1) ===

  /// Arranges for the next [connect] call to [deviceId] to throw a
  /// [PlatformConnectFailedException] with [reason] (and optional raw
  /// [status] / [message]), then clears automatically — a retry
  /// connects normally. Per-device and one-shot, mirroring how a real
  /// platform reports a single failed attempt.
  ///
  /// Sugar over [enqueueFault]; repeated calls stack as ordered rules.
  void simulateConnectFailure(
    String deviceId,
    PlatformConnectFailureReason reason, {
    int? status,
    String? message,
  }) {
    enqueueFault(
      FakeOp.connect,
      PlatformConnectFailedException(reason, status: status, message: message),
      deviceId: deviceId,
    );
  }

  /// When non-null, the next call to [connect] parks on this gate
  /// instead of completing immediately. Consumed (set to null) as soon
  /// as the connect call fires, so a subsequent connect falls through
  /// to normal handling. Mirrors the `_heldWrite` two-slot pattern.
  Completer<void>? _heldConnect;

  /// Once a held connect has been consumed by [connect], the gate is
  /// parked here so [resolveHeldConnect]/[failHeldConnect] can find it.
  Completer<void>? _heldConnectInFlight;

  /// Arranges for the next [connect] call to be held. While held, the
  /// timeout carried in the connect config is enforced with a [Timer]
  /// (so `fakeAsync.elapse` drives it): crossing it fails the connect
  /// with `PlatformConnectFailedException(timeout)`, matching the
  /// native connect-timeout contract. Call [resolveHeldConnect] to let
  /// the connect complete normally or [failHeldConnect] to fail it.
  void holdNextConnect() {
    _heldConnect = Completer<void>();
  }

  /// Releases the currently-held connect so it completes its normal
  /// path (peripheral lookup, state wiring, `connected` emission).
  void resolveHeldConnect() {
    final held = _heldConnectInFlight ?? _heldConnect;
    if (held == null) {
      throw StateError('No held connect to resolve');
    }
    _heldConnect = null;
    _heldConnectInFlight = null;
    held.complete();
  }

  /// Fails the currently-held connect with [error].
  void failHeldConnect(Object error) {
    final held = _heldConnectInFlight ?? _heldConnect;
    if (held == null) {
      throw StateError('No held connect to fail');
    }
    _heldConnect = null;
    _heldConnectInFlight = null;
    held.completeError(error);
  }

  /// When true, [setBluetoothState] to a non-`on` state also models the
  /// *transport* consequences of losing the adapter (audit R6 / NT-4):
  /// live outgoing connections drop with a `disconnected` state event,
  /// connected centrals are disconnected, scanning and advertising stop,
  /// and held in-flight operations are drained with
  /// [GattOperationDisconnectedException] (connects with
  /// [PlatformConnectFailedException]). Defaults to false — the
  /// historical event-only behavior existing tests rely on.
  bool cascadeAdapterTeardown = false;

  /// Sets the Bluetooth state and notifies listeners.
  void setBluetoothState(BluetoothState state) {
    _state = state;
    if (!suppressInitialStateEmission) {
      _stateController.add(state);
    }
    if (cascadeAdapterTeardown && state != BluetoothState.on) {
      _teardownTransport();
    }
  }

  /// Models the transport dying with the adapter. See
  /// [cascadeAdapterTeardown].
  void _teardownTransport() {
    for (final deviceId in _connections.keys.toList()) {
      simulateDisconnection(deviceId);
    }
    for (final centralId in _connectedCentrals.keys.toList()) {
      simulateCentralDisconnection(centralId);
    }
    _isScanningPlatform = false;
    _isAdvertising = false;
    _advertiseConfig = null;

    // Drain held in-flight ops the way a real platform queue drains on
    // adapter loss.
    final heldWrite = _heldWriteInFlight ?? _heldWrite;
    if (heldWrite != null && !heldWrite.isCompleted) {
      _heldWrite = null;
      _heldWriteInFlight = null;
      heldWrite.completeError(
        const GattOperationDisconnectedException('writeCharacteristic'),
      );
    }
    final heldRead = _heldReadInFlight ?? _heldRead;
    if (heldRead != null && !heldRead.isCompleted) {
      _heldRead = null;
      _heldReadInFlight = null;
      heldRead.completeError(
        const GattOperationDisconnectedException('readCharacteristic'),
      );
    }
    final heldConnect = _heldConnectInFlight ?? _heldConnect;
    if (heldConnect != null && !heldConnect.isCompleted) {
      _heldConnect = null;
      _heldConnectInFlight = null;
      heldConnect.completeError(
        const PlatformConnectFailedException(
          PlatformConnectFailureReason.unknown,
          message: 'adapter powered off during connect',
        ),
      );
    }
  }

  /// Test seam — update the simulated adapter state and broadcast.
  ///
  /// Equivalent to [setBluetoothState]; this shorter alias matches the
  /// naming convention used in factory-pre-check tests.
  void setState(BluetoothState state) {
    setBluetoothState(state);
  }

  /// Test seam — emit an error on the adapter-state stream. Exercises
  /// the defensive `onError` paths on per-instance adapter-state
  /// listeners in `BlueyScanner`, `BlueyConnection`, and `BlueyServer`.
  void simulateStateError(Object error) {
    _stateController.addError(error);
  }

  /// Simulates a peripheral device that can be discovered and connected to.
  void simulatePeripheral({
    required String id,
    String? name,
    int rssi = -50,
    List<String> serviceUuids = const [],
    int? manufacturerDataCompanyId,
    List<int>? manufacturerData,
    List<PlatformService> services = const [],
    Map<String, Uint8List> characteristicValues = const {},
  }) {
    _peripherals[id] = _SimulatedPeripheral(
      device: PlatformDevice(
        id: id,
        name: name,
        rssi: rssi,
        serviceUuids: serviceUuids,
        manufacturerDataCompanyId: manufacturerDataCompanyId,
        manufacturerData: manufacturerData,
      ),
      services: services,
      characteristicValues: Map.from(characteristicValues),
    );
  }

  /// Simulates a Bluey server advertising the control service with a
  /// pre-populated serverId characteristic.
  void simulateBlueyServer({
    required String address,
    required ServerId serverId,
    String name = 'Bluey Server',
    Duration intervalValue = const Duration(seconds: 10),
  }) {
    simulatePeripheral(
      id: address,
      name: name,
      serviceUuids: [controlServiceUuid],
      services: [
        PlatformService(
          uuid: controlServiceUuid,
          isPrimary: true,
          characteristics: const [
            PlatformCharacteristic(
              uuid: 'b1e70002-0000-1000-8000-00805f9b34fb',
              properties: PlatformCharacteristicProperties(
                canRead: false,
                canWrite: true,
                canWriteWithoutResponse: false,
                canNotify: false,
                canIndicate: false,
              ),
              descriptors: [],
              handle: 0,
            ),
            PlatformCharacteristic(
              uuid: 'b1e70003-0000-1000-8000-00805f9b34fb',
              properties: PlatformCharacteristicProperties(
                canRead: true,
                canWrite: false,
                canWriteWithoutResponse: false,
                canNotify: false,
                canIndicate: false,
              ),
              descriptors: [],
              handle: 0,
            ),
            PlatformCharacteristic(
              uuid: 'b1e70004-0000-1000-8000-00805f9b34fb',
              properties: PlatformCharacteristicProperties(
                canRead: true,
                canWrite: false,
                canWriteWithoutResponse: false,
                canNotify: false,
                canIndicate: false,
              ),
              descriptors: [],
              handle: 0,
            ),
            // Presence char: notify-only. The client subscribes to this on
            // connect so the iOS server learns of the disconnect via
            // didUnsubscribe when the link drops.
            PlatformCharacteristic(
              uuid: 'b1e70005-0000-1000-8000-00805f9b34fb',
              properties: PlatformCharacteristicProperties(
                canRead: false,
                canWrite: false,
                canWriteWithoutResponse: false,
                canNotify: true,
                canIndicate: false,
              ),
              descriptors: [],
              handle: 0,
            ),
          ],
          includedServices: [],
        ),
      ],
      characteristicValues: {
        'b1e70003-0000-1000-8000-00805f9b34fb': encodeInterval(intervalValue),
        'b1e70004-0000-1000-8000-00805f9b34fb': lifecycleCodec
            .encodeAdvertisedIdentity(serverId),
      },
    );
  }

  /// Removes a simulated peripheral.
  void removePeripheral(String id) {
    _peripherals.remove(id);
  }

  /// Simulates a central connecting to our server.
  ///
  /// Deliberately does NOT require advertising to be active (I348):
  /// real platforms deliver centrals regardless — most notably iOS's
  /// cached connection "reconnecting" the moment a new GATT server
  /// opens, before advertising starts. The natives report all
  /// connections to Dart immediately, and so does the fake.
  void simulateCentralConnection({required String centralId, int mtu = 23}) {
    _connectedCentrals[centralId] = _ConnectedCentral(
      id: centralId,
      mtu: mtu,
      subscribedCharacteristics: {},
    );
    _centralConnectionController.add(PlatformCentral(id: centralId, mtu: mtu));
  }

  /// Test-only: records a central that the (reused) native manager still
  /// "tracks" but the next-created [BlueyServer] has not heard of. On the next
  /// [resetServerSessions] it is re-announced via `centralConnections`,
  /// modelling the native re-announce contract (I338 reset-on-init).
  ///
  /// Unlike [simulateCentralConnection], this does not require advertising to
  /// be active — survivors pre-date the current advertising lifecycle, and the
  /// reset fires at server construction before startAdvertising.
  void simulateSurvivingAnnouncedCentral(String centralId, {int mtu = 23}) {
    _survivingAnnounced[centralId] = mtu;
  }

  /// Test-only helper: arms the lifecycle silence timer for [centralId] by
  /// sending a heartbeat write from that central.
  ///
  /// After calling this, advance fake time by the lifecycle interval (e.g.
  /// `async.elapse(lifecycleInterval)` inside a `fakeAsync` block) to
  /// actually fire the silence timeout and observe the domain-layer
  /// behaviour under test.
  ///
  /// This mirrors the pattern used in `lifecycle_test.dart`: the timer
  /// is armed by the first heartbeat write from a central; silence fires
  /// when no further heartbeat arrives within the configured interval.
  void fireLifecycleSilence(String centralId) {
    // A heartbeat write to the lifecycle control characteristic arms the
    // silence timer in LifecycleServer. We piggyback on the existing
    // write-request plumbing so the fake stays the single source of
    // truth for simulated write traffic. The specific sender identity
    // is irrelevant for silence-timeout tests — any valid heartbeat
    // payload will arm the timer.
    final payload = lifecycleCodec.encodeMessage(
      Heartbeat(ServerId('ffffffff-ffff-4fff-ffff-ffffffffffff')),
    );
    _writeRequestController.add(
      PlatformWriteRequest(
        requestId: _nextRequestId++,
        centralId: centralId,
        characteristicUuid: heartbeatCharUuid,
        value: payload,
        offset: 0,
        responseNeeded: false,
        characteristicHandle: 0,
      ),
    );
  }

  /// Simulates a central disconnecting from our server.
  void simulateCentralDisconnection(String centralId) {
    _connectedCentrals.remove(centralId);
    _centralDisconnectionController.add(centralId);
    final link = _inboundLink;
    if (link != null && link.centralId == centralId) {
      link.central.simulateDisconnection(link.deviceId);
      link._teardownSharedSibling();
    }
  }

  /// Models an iOS link loss where `didUnsubscribe` did NOT fire (the flaky
  /// case): the transport central is gone, but NO `centralDisconnections`
  /// signal is emitted — so the server never learns. Used to make Pattern B's
  /// empirical dependency on `didUnsubscribe` reliability explicit.
  void simulateSilentLinkLoss(String centralId) {
    _connectedCentrals.remove(centralId);
    // Deliberately does NOT add to _centralDisconnectionController.
  }

  /// Simulates a read request from a connected central.
  Future<Uint8List> simulateReadRequest({
    required String centralId,
    required String characteristicUuid,
    int offset = 0,
  }) {
    if (!_connectedCentrals.containsKey(centralId)) {
      throw StateError('Central $centralId is not connected');
    }
    if (_blackholedCentrals.contains(centralId)) {
      return _blackholeRequest<Uint8List>('readCharacteristic');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<Uint8List>();
    _pendingReadRequests[requestId] = completer;

    final handle =
        _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    _readRequestController.add(
      PlatformReadRequest(
        requestId: requestId,
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        offset: offset,
        characteristicHandle: handle,
      ),
    );

    return completer.future;
  }

  /// Simulates a write request from a connected central.
  Future<void> simulateWriteRequest({
    required String centralId,
    required String characteristicUuid,
    required Uint8List value,
    int offset = 0,
    bool responseNeeded = true,
  }) {
    if (!_connectedCentrals.containsKey(centralId)) {
      throw StateError('Central $centralId is not connected');
    }
    if (_blackholedCentrals.contains(centralId)) {
      return _blackholeRequest<void>('writeCharacteristic');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pendingWriteRequests[requestId] = completer;

    final handle =
        _localHandleByCharUuid[characteristicUuid.toLowerCase()] ?? 0;
    _writeRequestController.add(
      PlatformWriteRequest(
        requestId: requestId,
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        value: value,
        offset: offset,
        responseNeeded: responseNeeded,
        characteristicHandle: handle,
      ),
    );

    if (!responseNeeded) {
      completer.complete();
    }

    return completer.future;
  }

  /// Simulates the peripheral disconnecting from us (as central).
  void simulateDisconnection(String deviceId) {
    final connection = _connections[deviceId];
    if (connection != null) {
      _connections.remove(deviceId);
      connection.stateController.add(PlatformConnectionState.disconnected);
    }
    _failParkedWrites(deviceId);
    _clearHandles(deviceId);
  }

  /// Simulates a notification from a connected peripheral.
  void simulateNotification({
    required String deviceId,
    required String characteristicUuid,
    required Uint8List value,
  }) {
    final controller = _notificationControllers[deviceId];
    controller?.add(
      PlatformNotification(
        deviceId: deviceId,
        characteristicUuid: characteristicUuid,
        value: value,
      ),
    );
  }

  /// Simulates a service change notification for a connected peripheral.
  ///
  /// Optionally updates the simulated peripheral's services before firing,
  /// so that the next [discoverServices] call returns [newServices].
  void simulateServiceChange(
    String deviceId, {
    List<PlatformService>? newServices,
    Map<String, Uint8List>? newCharacteristicValues,
  }) {
    if (newServices != null || newCharacteristicValues != null) {
      final existingPeripheral = _peripherals[deviceId];
      if (existingPeripheral != null) {
        _peripherals[deviceId] = _SimulatedPeripheral(
          device: existingPeripheral.device,
          services: newServices ?? existingPeripheral.services,
          characteristicValues:
              newCharacteristicValues != null
                  ? Map.from(newCharacteristicValues)
                  : existingPeripheral.characteristicValues,
        );
        // Also update the connected device's peripheral reference
        final connection = _connections[deviceId];
        if (connection != null) {
          _connections[deviceId] = _ConnectedDevice(
            peripheral: _peripherals[deviceId]!,
            stateController: connection.stateController,
            notificationController: connection.notificationController,
            mtu: connection.mtu,
            subscribedCharacteristics: connection.subscribedCharacteristics,
          );
        }
      }
    }
    _clearHandles(deviceId);
    _serviceChangesController.add(deviceId);
  }

  /// Whether the fake platform is currently scanning (central role).
  /// Test seam — flipped to true on the first event delivery inside [scan]
  /// and back to false when [stopScan] is called.
  bool _isScanningPlatform = false;

  /// Whether the fake platform scan is currently active.
  /// Exposed as a test seam so tests can assert that cancelling the
  /// consumer's subscription stops the radio (Convention 5 / I335).
  bool get isScanning => _isScanningPlatform;

  /// Gets whether we're currently advertising.
  bool get isAdvertising => _isAdvertising;

  /// Gets the current advertise config.
  PlatformAdvertiseConfig? get advertiseConfig => _advertiseConfig;

  /// Gets the list of connected centrals.
  List<String> get connectedCentralIds => _connectedCentrals.keys.toList();

  /// Gets the list of currently connected peripheral addresses
  /// (the central-role view: devices we have outgoing connections to).
  List<String> get connectedDeviceIds => _connections.keys.toList();

  /// Gets the local services.
  List<PlatformLocalService> get localServices =>
      List.unmodifiable(_localServices);

  // === BlueyPlatform Implementation ===

  @override
  Capabilities get capabilities => _capabilities;

  @override
  Future<void> configure(BlueyConfig config) async {
    // No-op for fake
  }

  @override
  Stream<BluetoothState> get stateStream => _stateController.stream;

  @override
  BluetoothState get currentState =>
      suppressInitialStateEmission ? BluetoothState.unknown : _state;

  @override
  Future<BluetoothState> getState() async => _state;

  @override
  Future<bool> requestEnable() async {
    if (_state == BluetoothState.off) {
      setBluetoothState(BluetoothState.on);
      return true;
    }
    return _state == BluetoothState.on;
  }

  @override
  Future<bool> authorize() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<PlatformDevice> scan(PlatformScanConfig config) {
    lastScanConfig = config;
    _isScanningPlatform = true;
    // Create a new controller for each scan to avoid "closed stream" issues
    final scanController = StreamController<PlatformDevice>.broadcast();

    final scanFailure = _pendingScanFailure;
    if (scanFailure != null) {
      _pendingScanFailure = null;
      Future(() {
        if (!scanController.isClosed) {
          scanController.addError(scanFailure);
          scanController.close();
        }
        _isScanningPlatform = false;
      });
      return scanController.stream;
    }

    // Emit all simulated peripherals that match the filter
    Future(() {
      for (final peripheral in _peripherals.values) {
        // Filter by service UUIDs if specified
        if (config.serviceUuids.isNotEmpty) {
          final hasMatchingService = peripheral.device.serviceUuids.any(
            (uuid) => config.serviceUuids.contains(uuid),
          );
          if (!hasMatchingService) continue;
        }
        if (!scanController.isClosed) {
          scanController.add(peripheral.device);
        }
      }
    });

    return scanController.stream;
  }

  @override
  Future<void> stopScan() async {
    _isScanningPlatform = false;
  }

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    lastConnectConfig = config;

    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(FakeOp.connect, deviceId: deviceId);

    final held = _heldConnect;
    if (held != null) {
      _heldConnect = null;
      _heldConnectInFlight = held;
      // Enforce the caller's connect timeout while held — the only
      // window in which the fake's connect is ever in flight. Uses a
      // Timer so fakeAsync.elapse drives it deterministically.
      Timer? timeoutTimer;
      final timeoutMs = config.timeoutMs;
      if (timeoutMs != null) {
        timeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
          if (!held.isCompleted) {
            _heldConnectInFlight = null;
            held.completeError(
              const PlatformConnectFailedException(
                PlatformConnectFailureReason.timeout,
              ),
            );
          }
        });
      }
      try {
        await held.future;
      } finally {
        timeoutTimer?.cancel();
      }
    }

    final peripheral = _peripherals[deviceId];
    if (peripheral == null) {
      throw Exception('Device not found: $deviceId');
    }

    final stateController =
        StreamController<PlatformConnectionState>.broadcast();
    final notificationController =
        StreamController<PlatformNotification>.broadcast();

    _connectionStateControllers[deviceId] = stateController;
    _notificationControllers[deviceId] = notificationController;

    _connections[deviceId] = _ConnectedDevice(
      peripheral: peripheral,
      stateController: stateController,
      notificationController: notificationController,
      mtu: config.mtu ?? 23,
      subscribedCharacteristics: {},
    );

    stateController.add(PlatformConnectionState.connected);

    final link = _outboundLink;
    if (link != null && link.deviceId == deviceId) {
      // The far end is a real Bluey server riding the linked fake:
      // surface this connect as an inbound central there.
      link.peripheral.simulateCentralConnection(
        centralId: link.centralId,
        mtu: config.mtu ?? link.mtu,
      );
    }

    return deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final connection = _connections.remove(deviceId);
    if (connection != null) {
      connection.stateController.add(PlatformConnectionState.disconnected);
      await connection.stateController.close();
      await connection.notificationController.close();
      _connectionStateControllers.remove(deviceId);
      _notificationControllers.remove(deviceId);
      final link = _outboundLink;
      if (link != null && link.deviceId == deviceId) {
        link.peripheral.simulateCentralDisconnection(link.centralId);
        link._teardownSharedSibling();
      }
    }
    _failParkedWrites(deviceId);
    _clearHandles(deviceId);
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    return _connectionStateControllers[deviceId]?.stream ??
        Stream.value(PlatformConnectionState.disconnected);
  }

  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    discoverServicesCalls.add(deviceId);
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(FakeOp.discoverServices, deviceId: deviceId);
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    final services = connection.peripheral.services;
    final state = _stateFor(deviceId);
    final out = <PlatformService>[];
    for (var sIdx = 0; sIdx < services.length; sIdx++) {
      out.add(
        _withHandles(state, connection.peripheral, services[sIdx], '$sIdx'),
      );
    }
    return out;
  }

  PlatformService _withHandles(
    _DeviceState state,
    _SimulatedPeripheral peripheral,
    PlatformService service,
    String servicePath,
  ) {
    final chars = <PlatformCharacteristic>[];
    for (var cIdx = 0; cIdx < service.characteristics.length; cIdx++) {
      chars.add(
        _characteristicWithHandle(
          state,
          peripheral,
          service.characteristics[cIdx],
          '$servicePath/$cIdx',
        ),
      );
    }
    final included = <PlatformService>[];
    for (var iIdx = 0; iIdx < service.includedServices.length; iIdx++) {
      included.add(
        _withHandles(
          state,
          peripheral,
          service.includedServices[iIdx],
          '$servicePath/i$iIdx',
        ),
      );
    }
    return PlatformService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: chars,
      includedServices: included,
    );
  }

  PlatformCharacteristic _characteristicWithHandle(
    _DeviceState state,
    _SimulatedPeripheral peripheral,
    PlatformCharacteristic c,
    String charPath,
  ) {
    final handle = state.charHandleByPath.putIfAbsent(
      charPath,
      () => state.mintHandle(),
    );
    final uuidKey = c.uuid.toLowerCase();
    // UUID -> handles reverse lookup (multiple handles per UUID for
    // duplicate-UUID peripherals). The list is kept stable in
    // discovery (= tree) order.
    final handlesForUuid = state.charHandlesByUuid.putIfAbsent(
      uuidKey,
      () => <int>[],
    );
    if (!handlesForUuid.contains(handle)) {
      handlesForUuid.add(handle);
    }
    // Handle -> UUID reverse lookup (1:1).
    state.charUuidByHandle[handle] = uuidKey;

    // Seed the per-handle value from the UUID-keyed seed map on first
    // discovery, but never clobber a value that has already been
    // written/seeded against the handle directly. Re-discoveries (e.g.
    // post-Service-Changed with new handles) re-seed under the new
    // handle naturally.
    final seed =
        peripheral.characteristicValues[c.uuid] ??
        peripheral.characteristicValues[uuidKey];
    if (seed != null) {
      state.charValuesByHandle.putIfAbsent(
        handle,
        () => Uint8List.fromList(seed),
      );
    }

    final descs = <PlatformDescriptor>[];
    for (var dIdx = 0; dIdx < c.descriptors.length; dIdx++) {
      descs.add(
        _descriptorWithHandle(
          state,
          handle,
          c.descriptors[dIdx],
          '$charPath/$dIdx',
        ),
      );
    }
    return PlatformCharacteristic(
      uuid: c.uuid,
      properties: c.properties,
      descriptors: descs,
      handle: handle,
    );
  }

  PlatformDescriptor _descriptorWithHandle(
    _DeviceState state,
    int parentCharHandle,
    PlatformDescriptor d,
    String descPath,
  ) {
    // Descriptor handles are minted by tree position so the same
    // descriptor UUID under two different characteristic instances
    // gets distinct handles.
    final handle = state.descriptorHandleByPath.putIfAbsent(
      descPath,
      () => state.mintHandle(),
    );

    // For CCCDs, record the parent char -> CCCD handle mapping so
    // [setNotification] can write the CCCD value to the right slot.
    // Also seed a default value of [0x00, 0x00] (disabled) the first
    // time we see this CCCD on this connection.
    if (d.uuid.toLowerCase() == _cccdUuid) {
      state.cccdHandleByCharHandle[parentCharHandle] = handle;
      state.descriptorValuesByHandle.putIfAbsent(
        handle,
        () => Uint8List.fromList([0x00, 0x00]),
      );
    }
    return PlatformDescriptor(uuid: d.uuid, handle: handle);
  }

  void _clearHandles(String deviceId) {
    _deviceStates.remove(deviceId);
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    int characteristicHandle,
  ) async {
    readCharacteristicCalls.add(
      ReadCharacteristicCall(
        deviceId: deviceId,
        characteristicHandle: characteristicHandle,
        characteristicUuid:
            _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle] ??
            '',
      ),
    );

    final held = _heldRead;
    if (held != null) {
      _heldRead = null;
      _heldReadInFlight = held;
      return held.future;
    }

    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(
      FakeOp.readCharacteristic,
      deviceId: deviceId,
      characteristicUuid:
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle],
    );

    final code = simulateReadPlatformErrorCode;
    if (code != null) {
      simulateReadPlatformErrorCode = null;
      throw PlatformException(code: code);
    }
    final unknownCode = simulateReadUnknownPlatformExceptionCode;
    if (unknownCode != null) {
      simulateReadUnknownPlatformExceptionCode = null;
      final msg = simulateReadUnknownPlatformExceptionMessage;
      simulateReadUnknownPlatformExceptionMessage = null;
      throw GattOperationUnknownPlatformException(
        'readCharacteristic',
        code: unknownCode,
        message: msg,
      );
    }

    final pendingError = _pendingReadError;
    if (pendingError != null) {
      _pendingReadError = null;
      // ignore: only_throw_errors
      throw pendingError;
    }

    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    final link = _outboundLink;
    if (link != null && link.deviceId == deviceId) {
      final uuid =
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle] ?? '';
      return link.peripheral.simulateReadRequest(
        centralId: link.centralId,
        characteristicUuid: uuid,
      );
    }

    var state = _deviceStates[deviceId];
    if (state != null) {
      final value = state.charValuesByHandle[characteristicHandle];
      if (value != null) {
        return value;
      }
    }
    // Pre-discovery: if the test constructed a BlueyRemoteCharacteristic
    // by hand and called read() before services() ran, mint handles
    // eagerly from the simulated peripheral's tree so the seeded
    // characteristic value is reachable. The first encountered char
    // gets handle 1, matching the typical test fixture.
    final peripheral = _peripherals[deviceId];
    if (peripheral != null) {
      state = _stateFor(deviceId);
      _withHandlesAll(state, peripheral);
      final value = state.charValuesByHandle[characteristicHandle];
      if (value != null) {
        return value;
      }
    }
    throw Exception(
      'Characteristic not found for handle $characteristicHandle on $deviceId',
    );
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) {
    if (simulateSyncWriteThrow) {
      simulateSyncWriteThrow = false;
      throw StateError('simulated synchronous writeCharacteristic throw');
    }
    return _writeCharacteristicAsync(
      deviceId,
      characteristicHandle,
      value,
      withResponse,
    );
  }

  Future<void> _writeCharacteristicAsync(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) async {
    final held = _heldWrite;
    if (held != null) {
      _heldWrite = null;
      _heldWriteInFlight = held;
      return held.future;
    }

    // Pre-discovery: mint handles eagerly so this write lands at the
    // correct slot when the caller constructed a BlueyRemoteCharacteristic
    // by hand without going through `services()`. Done before the
    // simulate-failure guards so the recorded call carries the real
    // characteristic UUID even on simulated failures.
    final peripheral = _peripherals[deviceId];
    if (peripheral != null) {
      _withHandlesAll(_stateFor(deviceId), peripheral);
    }

    // Record attempts before failure simulation so tests can count
    // "writes the caller asked for" regardless of whether the platform
    // simulates a failure.
    writeCharacteristicCalls.add(
      WriteCharacteristicCall(
        deviceId: deviceId,
        characteristicHandle: characteristicHandle,
        characteristicUuid:
            _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle] ??
            '',
        value: Uint8List.fromList(value),
        withResponse: withResponse,
      ),
    );

    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(
      FakeOp.writeCharacteristic,
      deviceId: deviceId,
      characteristicUuid:
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle],
    );

    if (simulateWriteTimeout) {
      throw const GattOperationTimeoutException('writeCharacteristic');
    }
    if (simulateWriteDisconnected) {
      throw const GattOperationDisconnectedException('writeCharacteristic');
    }
    final status = simulateWriteStatusFailed;
    if (status != null) {
      throw GattOperationStatusFailedException('writeCharacteristic', status);
    }
    final code = simulateWritePlatformErrorCode;
    if (code != null) {
      throw PlatformException(code: code);
    }
    if (simulateWriteFailure) {
      throw Exception('Write failed: server unreachable');
    }

    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    final link = _outboundLink;
    if (link != null && link.deviceId == deviceId) {
      final uuid =
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle] ?? '';
      return link.peripheral.simulateWriteRequest(
        centralId: link.centralId,
        characteristicUuid: uuid,
        value: value,
        responseNeeded: withResponse,
      );
    }

    // Backpressure: a WWR write beyond the saturation budget parks
    // until drained (or failed by a link drop). With-response writes
    // are acked per-op by the peer and bypass the TX-queue model.
    if (!withResponse) {
      final budget = _wwrBudgets[deviceId];
      if (budget != null) {
        if (budget > 0) {
          _wwrBudgets[deviceId] = budget - 1;
        } else {
          final completer = Completer<void>();
          _parkedWrites.putIfAbsent(deviceId, () => []).add(completer);
          _stateFor(
            deviceId,
          ).charValuesByHandle[characteristicHandle] = Uint8List.fromList(value);
          return completer.future;
        }
      }
    }

    // Handle is the primary key.
    _stateFor(
      deviceId,
    ).charValuesByHandle[characteristicHandle] = Uint8List.fromList(value);
  }

  @override
  Future<void> setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  ) async {
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(
      FakeOp.setNotification,
      deviceId: deviceId,
      characteristicUuid:
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle],
    );
    if (simulateSetNotificationDisconnected) {
      throw const GattOperationDisconnectedException('setNotification');
    }
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    final state = _stateFor(deviceId);
    final charUuid = state.charUuidByHandle[characteristicHandle];
    setNotificationCalls.add(
      SetNotificationCall(
        deviceId: deviceId,
        characteristicHandle: characteristicHandle,
        characteristicUuid: charUuid ?? '',
        enable: enable,
      ),
    );
    if (charUuid != null) {
      if (enable) {
        connection.subscribedCharacteristics.add(charUuid);
      } else {
        connection.subscribedCharacteristics.remove(charUuid);
      }
      final link = _outboundLink;
      if (link != null && link.deviceId == deviceId) {
        final central = link.peripheral._connectedCentrals[link.centralId];
        if (enable) {
          central?.subscribedCharacteristics.add(charUuid);
        } else {
          central?.subscribedCharacteristics.remove(charUuid);
        }
      }
    }

    // Write the CCCD value at the descriptor handle that belongs to
    // THIS characteristic instance. Without this, two chars sharing a
    // UUID would share a single CCCD slot (I011). The CCCD bytes are
    // little-endian: 0x0001 = notifications, 0x0002 = indications,
    // 0x0000 = disabled. We only emit the notify-or-disable forms here
    // because the platform's `setNotification` API doesn't let the
    // domain side request indications independently — that path goes
    // through `subscribeIndicate`, which the fake doesn't model
    // separately.
    final cccdHandle = state.cccdHandleByCharHandle[characteristicHandle];
    if (cccdHandle != null) {
      state.descriptorValuesByHandle[cccdHandle] = Uint8List.fromList(
        enable ? [0x01, 0x00] : [0x00, 0x00],
      );
    }
  }

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) {
    return _notificationControllers[deviceId]?.stream ?? const Stream.empty();
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
  ) async {
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(
      FakeOp.readDescriptor,
      deviceId: deviceId,
      characteristicUuid:
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle],
    );
    final value =
        _deviceStates[deviceId]?.descriptorValuesByHandle[descriptorHandle];
    if (value != null) return value;
    return Uint8List(0);
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  ) async {
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(
      FakeOp.writeDescriptor,
      deviceId: deviceId,
      characteristicUuid:
          _deviceStates[deviceId]?.charUuidByHandle[characteristicHandle],
    );
    _stateFor(
      deviceId,
    ).descriptorValuesByHandle[descriptorHandle] = Uint8List.fromList(value);
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(FakeOp.requestMtu, deviceId: deviceId);
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    final cap = _mtuNegotiationCaps[deviceId];
    final negotiated = cap == null ? mtu : (mtu < cap ? mtu : cap);
    connection.mtu = negotiated;
    return negotiated;
  }

  /// Per-device override for the value returned from
  /// [getMaximumWriteLength]. Tests that need to assert on
  /// platform-asymmetry between writes-with-response and
  /// writes-without-response can populate both keys; tests that don't
  /// care fall back to the simulated peripheral's MTU minus 3.
  final Map<String, ({int withResponse, int withoutResponse})>
  _maxWriteOverrides = {};

  /// Override the value returned from [getMaximumWriteLength] for
  /// [deviceId]. Used by tests that need explicit control over the
  /// platform-reported payload limit.
  void setMaxWriteLengthOverride(
    String deviceId, {
    required int withResponse,
    required int withoutResponse,
  }) {
    _maxWriteOverrides[deviceId] = (
      withResponse: withResponse,
      withoutResponse: withoutResponse,
    );
  }

  @override
  Future<int> getMaximumWriteLength(
    String deviceId, {
    required bool withResponse,
  }) async {
    final override = _maxWriteOverrides[deviceId];
    if (override != null) {
      return withResponse ? override.withResponse : override.withoutResponse;
    }
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    return connection.mtu - 3;
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final latency = operationLatency;
    if (latency != null) {
      await Future<void>.delayed(latency);
    }
    _applyFaultRules(FakeOp.readRssi, deviceId: deviceId);
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    return connection.peripheral.device.rssi;
  }

  // === Bonding Operations ===
  //
  // When [Capabilities.canBond] is false the fake mirrors Android's
  // post-I035-Stage-A behaviour: every bond method throws
  // [UnimplementedError]. This is what the domain-side capability gating
  // exists to avoid — calling these on a `canBond=false` platform must
  // be guarded. Tests that pass `canBond: false` rely on this throwing
  // behaviour to assert the gate is in place.

  @override
  Future<PlatformBondState> getBondState(String deviceId) async {
    if (!_capabilities.canBond) {
      throw UnimplementedError(
        'Fake: getBondState called on a canBond=false platform',
      );
    }
    return PlatformBondState.none;
  }

  @override
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    if (!_capabilities.canBond) {
      throw UnimplementedError(
        'Fake: bondStateStream called on a canBond=false platform',
      );
    }
    return Stream.empty();
  }

  @override
  Future<void> bond(String deviceId) async {
    if (!_capabilities.canBond) {
      throw UnimplementedError('Fake: bond called on a canBond=false platform');
    }
  }

  @override
  Future<void> removeBond(String deviceId) async {
    if (!_capabilities.canBond) {
      throw UnimplementedError(
        'Fake: removeBond called on a canBond=false platform',
      );
    }
  }

  @override
  Future<List<PlatformDevice>> getBondedDevices() async {
    if (!_capabilities.canBond) {
      throw UnimplementedError(
        'Fake: getBondedDevices called on a canBond=false platform',
      );
    }
    return [];
  }

  // === PHY Operations ===

  @override
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    if (!_capabilities.canRequestPhy) {
      throw UnimplementedError(
        'Fake: getPhy called on a canRequestPhy=false platform',
      );
    }
    return (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m);
  }

  @override
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    if (!_capabilities.canRequestPhy) {
      throw UnimplementedError(
        'Fake: phyStream called on a canRequestPhy=false platform',
      );
    }
    return Stream.empty();
  }

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    if (!_capabilities.canRequestPhy) {
      throw UnimplementedError(
        'Fake: requestPhy called on a canRequestPhy=false platform',
      );
    }
  }

  // === Connection Parameters ===

  @override
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    if (!_capabilities.canRequestConnectionParameters) {
      throw UnimplementedError(
        'Fake: getConnectionParameters called on a '
        'canRequestConnectionParameters=false platform',
      );
    }
    return const PlatformConnectionParameters(
      intervalMs: 30.0,
      latency: 0,
      timeoutMs: 4000,
    );
  }

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) async {
    if (!_capabilities.canRequestConnectionParameters) {
      throw UnimplementedError(
        'Fake: requestConnectionParameters called on a '
        'canRequestConnectionParameters=false platform',
      );
    }
  }

  // === Server Operations ===

  /// When non-null, the next call to [addService] consumes this completer
  /// instead of resolving immediately. Lets ordering tests verify that
  /// `startAdvertising` waits for an in-flight `addService` (I080).
  /// Once consumed, the completer is parked in [_heldAddServiceInFlight]
  /// so [resolveHeldAddService] can still find it (mirrors the
  /// `_heldWriteInFlight` pattern above).
  Completer<void>? _heldAddService;
  Completer<void>? _heldAddServiceInFlight;

  /// Arranges for the next [addService] call to be held indefinitely.
  /// Call [resolveHeldAddService] to release it.
  void holdNextAddService() {
    _heldAddService = Completer<void>();
  }

  /// Resolves the currently-held addService future. Works whether or
  /// not the held call has already been consumed.
  void resolveHeldAddService() {
    final held = _heldAddServiceInFlight ?? _heldAddService;
    if (held == null) {
      throw StateError('No held addService to resolve');
    }
    _heldAddService = null;
    _heldAddServiceInFlight = null;
    held.complete();
  }

  @override
  Future<PlatformLocalService> addService(PlatformLocalService service) async {
    final held = _heldAddService;
    if (held != null) {
      _heldAddService = null;
      _heldAddServiceInFlight = held;
      await held.future;
    }
    final populated = _populateLocalHandles(service);
    _localServices.add(populated);
    return populated;
  }

  /// Mints handles for every characteristic / descriptor in [service]
  /// and returns a populated copy. Mirrors the native server-role
  /// behaviour from [PeripheralManagerImpl.addService] (iOS) /
  /// [GattServer.populateHandles] (Android).
  PlatformLocalService _populateLocalHandles(PlatformLocalService service) {
    final populatedChars = <PlatformLocalCharacteristic>[];
    for (final c in service.characteristics) {
      final h = _nextLocalHandle++;
      _localHandleByCharUuid[c.uuid.toLowerCase()] = h;
      var nextDesc = 1;
      final populatedDescs =
          c.descriptors
              .map(
                (d) => PlatformLocalDescriptor(
                  uuid: d.uuid,
                  permissions: d.permissions,
                  value: d.value,
                  handle: nextDesc++,
                ),
              )
              .toList();
      populatedChars.add(
        PlatformLocalCharacteristic(
          uuid: c.uuid,
          properties: c.properties,
          permissions: c.permissions,
          descriptors: populatedDescs,
          handle: h,
        ),
      );
    }
    return PlatformLocalService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: populatedChars,
      includedServices:
          service.includedServices.map(_populateLocalHandles).toList(),
    );
  }

  @override
  Future<void> removeService(String serviceUuid) async {
    _localServices.removeWhere((s) => s.uuid == serviceUuid);
  }

  /// Test seam — when true, the next `startAdvertising` call throws.
  /// Reset to false automatically after firing once. Drives the
  /// rollback path in [BlueyServer.startAdvertising].
  bool advertisingShouldFail = false;

  @override
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
    if (advertisingShouldFail) {
      advertisingShouldFail = false;
      throw StateError('fake: startAdvertising rejected');
    }
    _isAdvertising = true;
    _advertiseConfig = config;
  }

  @override
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
    _advertiseConfig = null;
  }

  @override
  Future<void> notifyCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    // Notify all subscribed centrals. Resolve handle -> UUID for
    // subscription bookkeeping (the fake's central-side fixture tracks
    // subscriptions by UUID).
    final charUuid =
        _localHandleByCharUuid.entries
            .firstWhere(
              (e) => e.value == characteristicHandle,
              orElse: () => const MapEntry('', 0),
            )
            .key;
    if (charUuid.isEmpty) return;
    for (final central in _connectedCentrals.values) {
      if (central.subscribedCharacteristics.contains(charUuid)) {
        _deliverLinkedNotification(central.id, charUuid, value);
      }
    }
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    final central = _connectedCentrals[centralId];
    if (central == null) {
      throw Exception('Central not connected: $centralId');
    }
    final charUuid = _localHandleByCharUuid.entries
        .firstWhere(
          (e) => e.value == characteristicHandle,
          orElse: () => const MapEntry('', 0),
        )
        .key;
    if (charUuid.isNotEmpty &&
        central.subscribedCharacteristics.contains(charUuid)) {
      _deliverLinkedNotification(centralId, charUuid, value);
    }
  }

  @override
  Future<void> indicateCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {
    final charUuid =
        _localHandleByCharUuid.entries
            .firstWhere(
              (e) => e.value == characteristicHandle,
              orElse: () => const MapEntry('', 0),
            )
            .key;
    if (charUuid.isEmpty) return;
    for (final central in _connectedCentrals.values) {
      if (central.subscribedCharacteristics.contains(charUuid)) {
        _deliverLinkedNotification(central.id, charUuid, value);
      }
    }
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {
    final central = _connectedCentrals[centralId];
    if (central == null) {
      throw Exception('Central not connected: $centralId');
    }
    final charUuid = _localHandleByCharUuid.entries
        .firstWhere(
          (e) => e.value == characteristicHandle,
          orElse: () => const MapEntry('', 0),
        )
        .key;
    if (charUuid.isNotEmpty &&
        central.subscribedCharacteristics.contains(charUuid)) {
      _deliverLinkedNotification(centralId, charUuid, value);
    }
  }

  @override
  Stream<String> get serviceChanges => _serviceChangesController.stream;

  @override
  Stream<PlatformCentral> get centralConnections =>
      _centralConnectionController.stream;

  @override
  Stream<String> get centralDisconnections =>
      _centralDisconnectionController.stream;

  @override
  Stream<PlatformReadRequest> get readRequests => _readRequestController.stream;

  @override
  Stream<PlatformWriteRequest> get writeRequests =>
      _writeRequestController.stream;

  @override
  Future<void> respondToReadRequest(
    int requestId,
    PlatformGattStatus status,
    Uint8List? value,
  ) async {
    final injectedFailure = respondToReadFailure;
    if (injectedFailure != null) {
      respondToReadFailure = null; // one-shot
      throw injectedFailure;
    }
    respondReadCalls.add(
      RespondReadCall(requestId: requestId, status: status, value: value),
    );
    final completer = _pendingReadRequests.remove(requestId);
    if (completer != null) {
      if (status == PlatformGattStatus.success && value != null) {
        completer.complete(value);
      } else {
        completer.completeError(Exception('Read failed with status: $status'));
      }
    }
  }

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    PlatformGattStatus status,
  ) async {
    respondWriteCalls.add(
      RespondWriteCall(requestId: requestId, status: status),
    );
    final completer = _pendingWriteRequests.remove(requestId);
    if (completer != null) {
      if (status == PlatformGattStatus.success) {
        completer.complete();
      } else {
        completer.completeError(Exception('Write failed with status: $status'));
      }
    }
  }

  @override
  Future<void> closeServer() async {
    await stopAdvertising();
    for (final centralId in _connectedCentrals.keys.toList()) {
      simulateCentralDisconnection(centralId);
    }
    _localServices.clear();
  }

  @override
  Future<void> resetServerSessions() async {
    final survivors = Map<String, int>.from(_survivingAnnounced);
    _survivingAnnounced.clear();
    for (final entry in survivors.entries) {
      // Mirror a real re-announce: register transport + emit
      // centralConnections. Does not require advertising to be active — this
      // is called at server construction, before startAdvertising.
      _connectedCentrals[entry.key] = _ConnectedCentral(
        id: entry.key,
        mtu: entry.value,
        subscribedCharacteristics: {},
      );
      _centralConnectionController.add(
        PlatformCentral(id: entry.key, mtu: entry.value),
      );
    }
  }

  /// Disposes all resources.
  Future<void> dispose() async {
    await _stateController.close();
    await _serviceChangesController.close();
    await _centralConnectionController.close();
    await _centralDisconnectionController.close();
    await _readRequestController.close();
    await _writeRequestController.close();
    await _logEventsController.close();

    for (final controller in _connectionStateControllers.values) {
      await controller.close();
    }
    for (final controller in _notificationControllers.values) {
      await controller.close();
    }
  }
}

/// A virtual BLE link between two [FakeBlueyPlatform]s, so two real
/// Bluey endpoints — one GATT server, one client — exchange traffic
/// end-to-end (audit R4 / NT-6):
///
///  * a client `connect` to [deviceId] surfaces as an inbound central
///    [centralId] on the peripheral side (which must be advertising);
///  * client writes/reads become real `writeRequests`/`readRequests`
///    on the server, whose responses complete the client's futures;
///  * client subscriptions mirror onto the server's per-central
///    subscription set, and server notify/indicate delivers onto the
///    client's notification stream;
///  * disconnects propagate in both directions.
///
/// Usage: create both fakes, bind a Bluey instance to each (set
/// `BlueyPlatform.instance` before each `Bluey.create()`), construct
/// the link, host services + start advertising on the server side,
/// then call [announce] so the client side can discover the server.
class FakeBleLink {
  /// The fake behind the Bluey instance acting as GATT client.
  final FakeBlueyPlatform central;

  /// The fake behind the Bluey instance acting as GATT server.
  final FakeBlueyPlatform peripheral;

  /// The peripheral's identity in the central's world (scan/connect id).
  final String deviceId;

  /// The central's identity in the peripheral's world.
  final String centralId;

  /// MTU announced for the inbound central when the client connects
  /// without requesting one.
  final int mtu;

  FakeBleLink({
    required this.central,
    required this.peripheral,
    required this.deviceId,
    required this.centralId,
    this.mtu = 23,
  }) {
    central._outboundLink = this;
    peripheral._inboundLink = this;
  }

  /// The opposite-direction link riding the same physical connection,
  /// when [shareOnePhysicalLink] has bound this pair. iOS multiplexes
  /// one LL connection per peer pair across GAP roles; tearing either
  /// logical link down kills both (cross-platform-quirks.md §1, I346).
  FakeBleLink? _sharedWith;
  bool _tearingShared = false;

  /// Binds [a] and [b] — two opposite-direction links between the same
  /// pair of fakes — into the iOS one-physical-link topology:
  /// disconnecting either tears both down. Leave unbound for the
  /// Android topology (independent links).
  static void shareOnePhysicalLink(FakeBleLink a, FakeBleLink b) {
    a._sharedWith = b;
    b._sharedWith = a;
  }

  /// Tears the shared sibling link down after this link's own teardown.
  void _teardownSharedSibling() {
    final sibling = _sharedWith;
    if (sibling == null || _tearingShared || sibling._tearingShared) return;
    _tearingShared = true;
    sibling._tearingShared = true;
    sibling.central.simulateDisconnection(sibling.deviceId);
    sibling.peripheral.simulateCentralDisconnection(sibling.centralId);
    _tearingShared = false;
    sibling._tearingShared = false;
  }

  /// Snapshots the peripheral side's hosted services and registers them
  /// as a discoverable simulated peripheral on the central side. Call
  /// after the server has added its services (re-call after changes).
  void announce({String? name, int rssi = -50}) {
    final config = peripheral._advertiseConfig;
    central.simulatePeripheral(
      id: deviceId,
      name: name ?? config?.name,
      rssi: rssi,
      serviceUuids: [
        ...?config?.serviceUuids,
        ...?config?.scanResponseServiceUuids,
      ],
      services: peripheral._localServices.map(_asRemoteService).toList(),
    );
  }

  static PlatformService _asRemoteService(PlatformLocalService service) {
    return PlatformService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: [
        for (final c in service.characteristics)
          PlatformCharacteristic(
            uuid: c.uuid,
            properties: c.properties,
            descriptors: [
              for (final d in c.descriptors)
                PlatformDescriptor(uuid: d.uuid, handle: 0),
            ],
            handle: 0,
          ),
      ],
      includedServices:
          service.includedServices.map(_asRemoteService).toList(),
    );
  }
}

/// Operations that [FakeBlueyPlatform.enqueueFault] can target.
enum FakeOp {
  connect,
  discoverServices,
  readCharacteristic,
  writeCharacteristic,
  setNotification,
  readDescriptor,
  writeDescriptor,
  requestMtu,
  readRssi,
}

/// A scripted fault: fires [error] for matching calls to [op] until its
/// budget runs out ([remaining] `null` = unlimited).
class _FaultRule {
  final FakeOp op;
  final String? deviceId;
  final String? characteristicUuid; // lowercase
  final Object error;
  int? remaining;

  _FaultRule({
    required this.op,
    required this.deviceId,
    required this.characteristicUuid,
    required this.error,
    required this.remaining,
  });
}

// === Internal Helper Classes ===

/// Per-device handle-keyed storage. Handle is the primary identity for
/// every attribute; UUID is metadata used only by reverse-lookup paths
/// for legacy UUID-only call sites (which D.13 will remove).
///
/// All maps share a single per-device handle counter ([nextHandle])
/// drawn from a single pool for both characteristics and descriptors —
/// this matches the iOS implementation. Handle values start at 1.
class _DeviceState {
  /// Monotonic per-device handle counter. Single pool shared between
  /// characteristics and descriptors. Starts at 0; minted handles
  /// start at 1.
  int nextHandle = 0;

  /// Tree-position -> handle for characteristics. Keys are
  /// `'sIdx/cIdx'` (with `/iN` segments for included services). Lets
  /// re-discovery reuse handles for the same tree position.
  final Map<String, int> charHandleByPath = {};

  /// Tree-position -> handle for descriptors. Keys are
  /// `'sIdx/cIdx/dIdx'` (with `/iN` for included services).
  final Map<String, int> descriptorHandleByPath = {};

  /// UUID (lowercase) -> ordered list of handles. Multiple entries on
  /// duplicate-UUID peripherals; order matches discovery order.
  final Map<String, List<int>> charHandlesByUuid = {};

  /// Handle -> UUID (lowercase). 1:1.
  final Map<int, String> charUuidByHandle = {};

  /// Char handle -> CCCD descriptor handle (if any). Used by
  /// [setNotification] to write the CCCD value to the right slot for
  /// the right characteristic instance.
  final Map<int, int> cccdHandleByCharHandle = {};

  /// **Primary** handle-keyed value storage for characteristics.
  final Map<int, Uint8List> charValuesByHandle = {};

  /// **Primary** handle-keyed value storage for descriptors. Default
  /// CCCD entries (0x0000 = disabled) are seeded at discovery time.
  final Map<int, Uint8List> descriptorValuesByHandle = {};

  int mintHandle() {
    nextHandle += 1;
    return nextHandle;
  }
}

class _SimulatedPeripheral {
  final PlatformDevice device;
  final List<PlatformService> services;
  final Map<String, Uint8List> characteristicValues;

  _SimulatedPeripheral({
    required this.device,
    required this.services,
    required this.characteristicValues,
  });
}

class _ConnectedDevice {
  final _SimulatedPeripheral peripheral;
  final StreamController<PlatformConnectionState> stateController;
  final StreamController<PlatformNotification> notificationController;
  int mtu;
  final Set<String> subscribedCharacteristics;

  _ConnectedDevice({
    required this.peripheral,
    required this.stateController,
    required this.notificationController,
    required this.mtu,
    required this.subscribedCharacteristics,
  });
}

class _ConnectedCentral {
  final String id;
  final int mtu;
  final Set<String> subscribedCharacteristics;

  _ConnectedCentral({
    required this.id,
    required this.mtu,
    required this.subscribedCharacteristics,
  });
}

/// A recorded call to [FakeBlueyPlatform.respondToReadRequest].
class RespondReadCall {
  final int requestId;
  final PlatformGattStatus status;
  final Uint8List? value;

  RespondReadCall({
    required this.requestId,
    required this.status,
    required this.value,
  });
}

/// A recorded call to [FakeBlueyPlatform.respondToWriteRequest].
class RespondWriteCall {
  final int requestId;
  final PlatformGattStatus status;

  RespondWriteCall({required this.requestId, required this.status});
}

/// A recorded call to [FakeBlueyPlatform.readCharacteristic].
///
/// Carries both the wire-level [characteristicHandle] and the
/// fake-resolved [characteristicUuid] (lowercase) so existing tests
/// that filter by UUID stay working without requiring every assertion
/// to know about handles.
class ReadCharacteristicCall {
  final String deviceId;
  final int characteristicHandle;
  final String characteristicUuid;

  const ReadCharacteristicCall({
    required this.deviceId,
    required this.characteristicHandle,
    required this.characteristicUuid,
  });
}

/// A recorded call to [FakeBlueyPlatform.setNotification].
///
/// Carries both the wire-level [characteristicHandle] and the
/// fake-resolved [characteristicUuid] (lowercase) so tests can assert on
/// the subscribed characteristic by UUID without knowing the per-device
/// handle mapping.
class SetNotificationCall {
  final String deviceId;
  final int characteristicHandle;
  final String characteristicUuid;
  final bool enable;

  const SetNotificationCall({
    required this.deviceId,
    required this.characteristicHandle,
    required this.characteristicUuid,
    required this.enable,
  });
}

/// A recorded call to [FakeBlueyPlatform.writeCharacteristic].
class WriteCharacteristicCall {
  final String deviceId;
  final int characteristicHandle;
  final String characteristicUuid;
  final Uint8List value;
  final bool withResponse;

  WriteCharacteristicCall({
    required this.deviceId,
    required this.characteristicHandle,
    required this.characteristicUuid,
    required this.value,
    required this.withResponse,
  });
}

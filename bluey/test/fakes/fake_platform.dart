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
  FakeBlueyPlatform({Capabilities capabilities = Capabilities.fake})
    : _capabilities = capabilities,
      super.impl();

  // === Configuration ===
  BluetoothState _state = BluetoothState.on;
  final Capabilities _capabilities;

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

  /// Records every call to [respondToWriteRequest] in order.
  final List<RespondWriteCall> respondWriteCalls = [];

  /// Records every call to [writeCharacteristic] in order.
  final List<WriteCharacteristicCall> writeCharacteristicCalls = [];

  /// Records every call to [readCharacteristic] in order.
  final List<ReadCharacteristicCall> readCharacteristicCalls = [];

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

  /// Sets the Bluetooth state and notifies listeners.
  void setBluetoothState(BluetoothState state) {
    _state = state;
    _stateController.add(state);
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
  void simulateCentralConnection({required String centralId, int mtu = 23}) {
    if (!_isAdvertising) {
      throw StateError('Cannot connect central when not advertising');
    }
    _connectedCentrals[centralId] = _ConnectedCentral(
      id: centralId,
      mtu: mtu,
      subscribedCharacteristics: {},
    );
    _centralConnectionController.add(PlatformCentral(id: centralId, mtu: mtu));
  }

  /// Simulates a central disconnecting from our server.
  void simulateCentralDisconnection(String centralId) {
    _connectedCentrals.remove(centralId);
    _centralDisconnectionController.add(centralId);
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
    // Create a new controller for each scan to avoid "closed stream" issues
    final scanController = StreamController<PlatformDevice>.broadcast();

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
    // No-op - scanning is passive in fake
  }

  @override
  Future<String> connect(String deviceId, PlatformConnectConfig config) async {
    lastConnectConfig = config;
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
    }
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
    if (simulateSetNotificationDisconnected) {
      throw const GattOperationDisconnectedException('setNotification');
    }
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    final state = _stateFor(deviceId);
    final charUuid = state.charUuidByHandle[characteristicHandle];
    if (charUuid != null) {
      if (enable) {
        connection.subscribedCharacteristics.add(charUuid);
      } else {
        connection.subscribedCharacteristics.remove(charUuid);
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
    _stateFor(
      deviceId,
    ).descriptorValuesByHandle[descriptorHandle] = Uint8List.fromList(value);
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    connection.mtu = mtu;
    return mtu;
  }

  @override
  Future<int> readRssi(String deviceId) async {
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

  @override
  Future<void> startAdvertising(PlatformAdvertiseConfig config) async {
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
        // In a real implementation, this would send over BLE.
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
    // For testing purposes, we track this was called
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
        // In a real implementation, this would wait for acknowledgment.
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
    // For testing purposes, we track this was called
    // In a real implementation, this would wait for acknowledgment
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

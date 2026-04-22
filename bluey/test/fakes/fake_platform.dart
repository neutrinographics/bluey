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
final class FakeBlueyPlatform extends BlueyPlatform {
  FakeBlueyPlatform() : super.impl();

  // === Configuration ===
  BluetoothState _state = BluetoothState.on;
  final Capabilities _capabilities = const Capabilities(
    canScan: true,
    canConnect: true,
    canAdvertise: true,
  );

  // === Simulated Peripherals (devices we can discover/connect to) ===
  final Map<String, _SimulatedPeripheral> _peripherals = {};

  // === Connected Devices (as central) ===
  final Map<String, _ConnectedDevice> _connections = {};

  // === Server State (as peripheral) ===
  final List<PlatformLocalService> _localServices = [];
  bool _isAdvertising = false;
  PlatformAdvertiseConfig? _advertiseConfig;
  final Map<String, _ConnectedCentral> _connectedCentrals = {};
  int _nextRequestId = 1;

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

  /// When non-null, readCharacteristic throws a [PlatformException] with
  /// this [PlatformException.code]. Models platform-layer errors that are
  /// emitted BEFORE reaching the typed-exception translation helper (e.g.
  /// iOS Swift errors with codes not yet mapped by the platform adapter).
  String? simulateReadPlatformErrorCode;

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
            ),
          ],
          includedServices: [],
        ),
      ],
      characteristicValues: {
        'b1e70003-0000-1000-8000-00805f9b34fb': encodeInterval(intervalValue),
        'b1e70004-0000-1000-8000-00805f9b34fb': serverId.toBytes(),
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

    _readRequestController.add(
      PlatformReadRequest(
        requestId: requestId,
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        offset: offset,
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

    _writeRequestController.add(
      PlatformWriteRequest(
        requestId: requestId,
        centralId: centralId,
        characteristicUuid: characteristicUuid,
        value: value,
        offset: offset,
        responseNeeded: responseNeeded,
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
  void simulateServiceChange(String deviceId, {
    List<PlatformService>? newServices,
    Map<String, Uint8List>? newCharacteristicValues,
  }) {
    if (newServices != null || newCharacteristicValues != null) {
      final existingPeripheral = _peripherals[deviceId];
      if (existingPeripheral != null) {
        _peripherals[deviceId] = _SimulatedPeripheral(
          device: existingPeripheral.device,
          services: newServices ?? existingPeripheral.services,
          characteristicValues: newCharacteristicValues != null
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
    _serviceChangesController.add(deviceId);
  }

  /// Gets whether we're currently advertising.
  bool get isAdvertising => _isAdvertising;

  /// Gets the current advertise config.
  PlatformAdvertiseConfig? get advertiseConfig => _advertiseConfig;

  /// Gets the list of connected centrals.
  List<String> get connectedCentralIds => _connectedCentrals.keys.toList();

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
  }

  @override
  Stream<PlatformConnectionState> connectionStateStream(String deviceId) {
    return _connectionStateControllers[deviceId]?.stream ??
        Stream.value(PlatformConnectionState.disconnected);
  }

  @override
  Future<List<PlatformService>> discoverServices(String deviceId) async {
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }
    return connection.peripheral.services;
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String characteristicUuid,
  ) async {
    final code = simulateReadPlatformErrorCode;
    if (code != null) {
      simulateReadPlatformErrorCode = null;
      throw PlatformException(code: code);
    }

    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    final value =
        connection.peripheral.characteristicValues[characteristicUuid];
    if (value == null) {
      throw Exception('Characteristic not found: $characteristicUuid');
    }
    return value;
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
    bool withResponse,
  ) async {
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

    writeCharacteristicCalls.add(WriteCharacteristicCall(
      deviceId: deviceId,
      characteristicUuid: characteristicUuid,
      value: Uint8List.fromList(value),
      withResponse: withResponse,
    ));

    connection.peripheral.characteristicValues[characteristicUuid] = value;
  }

  @override
  Future<void> setNotification(
    String deviceId,
    String characteristicUuid,
    bool enable,
  ) async {
    if (simulateSetNotificationDisconnected) {
      throw const GattOperationDisconnectedException('setNotification');
    }
    final connection = _connections[deviceId];
    if (connection == null) {
      throw Exception('Not connected to device: $deviceId');
    }

    if (enable) {
      connection.subscribedCharacteristics.add(characteristicUuid);
    } else {
      connection.subscribedCharacteristics.remove(characteristicUuid);
    }
  }

  @override
  Stream<PlatformNotification> notificationStream(String deviceId) {
    return _notificationControllers[deviceId]?.stream ?? const Stream.empty();
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    String descriptorUuid,
  ) async {
    return Uint8List(0);
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    String descriptorUuid,
    Uint8List value,
  ) async {}

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

  @override
  Future<PlatformBondState> getBondState(String deviceId) async {
    return PlatformBondState.none;
  }

  @override
  Stream<PlatformBondState> bondStateStream(String deviceId) {
    return Stream.empty();
  }

  @override
  Future<void> bond(String deviceId) async {
    // Simulate bonding success
  }

  @override
  Future<void> removeBond(String deviceId) async {
    // Simulate bond removal
  }

  @override
  Future<List<PlatformDevice>> getBondedDevices() async {
    return [];
  }

  // === PHY Operations ===

  @override
  Future<({PlatformPhy tx, PlatformPhy rx})> getPhy(String deviceId) async {
    return (tx: PlatformPhy.le1m, rx: PlatformPhy.le1m);
  }

  @override
  Stream<({PlatformPhy tx, PlatformPhy rx})> phyStream(String deviceId) {
    return Stream.empty();
  }

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) async {
    // Simulate PHY request success
  }

  // === Connection Parameters ===

  @override
  Future<PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
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
    // Simulate connection parameters request success
  }

  // === Server Operations ===

  @override
  Future<void> addService(PlatformLocalService service) async {
    _localServices.add(service);
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
    String characteristicUuid,
    Uint8List value,
  ) async {
    // Notify all subscribed centrals
    for (final central in _connectedCentrals.values) {
      if (central.subscribedCharacteristics.contains(characteristicUuid)) {
        // In a real implementation, this would send over BLE
        // For testing, we can verify it was called
      }
    }
  }

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    String characteristicUuid,
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
    String characteristicUuid,
    Uint8List value,
  ) async {
    // Indicate all subscribed centrals (with acknowledgment)
    for (final central in _connectedCentrals.values) {
      if (central.subscribedCharacteristics.contains(characteristicUuid)) {
        // In a real implementation, this would wait for acknowledgment
      }
    }
  }

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    String characteristicUuid,
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
  Future<void> disconnectCentral(String centralId) async {
    simulateCentralDisconnection(centralId);
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

    for (final controller in _connectionStateControllers.values) {
      await controller.close();
    }
    for (final controller in _notificationControllers.values) {
      await controller.close();
    }
  }
}

// === Internal Helper Classes ===

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

  RespondWriteCall({
    required this.requestId,
    required this.status,
  });
}

/// A recorded call to [FakeBlueyPlatform.writeCharacteristic].
class WriteCharacteristicCall {
  final String deviceId;
  final String characteristicUuid;
  final Uint8List value;
  final bool withResponse;

  WriteCharacteristicCall({
    required this.deviceId,
    required this.characteristicUuid,
    required this.value,
    required this.withResponse,
  });
}

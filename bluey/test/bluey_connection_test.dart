import 'dart:async';
import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
// ignore: implementation_imports
import 'package:bluey/src/log/bluey_logger.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

/// Mock platform for testing BlueyConnection.
final class MockBlueyPlatform extends platform.BlueyPlatform {
  MockBlueyPlatform() : super.impl();
  // Services to return from discoverServices
  List<platform.PlatformService> mockServices = [];

  // Characteristic values for read operations, keyed by lowercase UUID.
  // The mock minted handles in [_withMintedHandles] are tracked here so
  // handle-keyed reads can resolve back to the seed UUID.
  Map<String, Uint8List> characteristicValues = {};

  // Descriptor values for read operations, keyed by lowercase UUID.
  Map<String, Uint8List> descriptorValues = {};

  /// handle -> UUID, populated as [_withMintedHandles] mints handles.
  final Map<int, String> _charUuidByHandle = {};
  final Map<int, String> _descUuidByHandle = {};

  // Track write calls
  List<WriteCharacteristicCall> writeCharacteristicCalls = [];
  List<WriteDescriptorCall> writeDescriptorCalls = [];

  // Track setNotification calls
  List<SetNotificationCall> setNotificationCalls = [];

  // MTU to return
  int mockMtu = 512;

  // RSSI to return
  int mockRssi = -60;

  // Connection state controller
  final _connectionStateControllers =
      <String, StreamController<platform.PlatformConnectionState>>{};

  // Notification controllers
  final _notificationControllers =
      <String, StreamController<platform.PlatformNotification>>{};

  @override
  platform.Capabilities get capabilities => platform.Capabilities.android;

  @override
  Future<void> configure(platform.BlueyConfig config) async {}

  @override
  Stream<platform.BluetoothState> get stateStream =>
      Stream.value(platform.BluetoothState.on);

  @override
  Future<platform.BluetoothState> getState() async =>
      platform.BluetoothState.on;

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<bool> authorize() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<platform.PlatformDevice> scan(platform.PlatformScanConfig config) =>
      const Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> connect(
    String deviceId,
    platform.PlatformConnectConfig config,
  ) async {
    _connectionStateControllers[deviceId] =
        StreamController<platform.PlatformConnectionState>.broadcast();
    _notificationControllers[deviceId] =
        StreamController<platform.PlatformNotification>.broadcast();
    return deviceId;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _connectionStateControllers[deviceId]?.close();
    _connectionStateControllers.remove(deviceId);
    await _notificationControllers[deviceId]?.close();
    _notificationControllers.remove(deviceId);
  }

  @override
  Stream<platform.PlatformConnectionState> connectionStateStream(
    String deviceId,
  ) {
    return _connectionStateControllers[deviceId]?.stream ??
        Stream.error(StateError('Not connected'));
  }

  @override
  Future<List<platform.PlatformService>> discoverServices(
    String deviceId,
  ) async {
    return mockServices.map(_withMintedHandles).toList();
  }

  // Per-mock monotonic counter shared by chars + descs. Tests pass
  // PlatformCharacteristic / PlatformDescriptor without handles for
  // brevity; we mint them here so [BlueyConnection._mapCharacteristic]
  // doesn't trip its non-null assertion.
  int _nextHandle = 0;

  platform.PlatformService _withMintedHandles(platform.PlatformService s) {
    return platform.PlatformService(
      uuid: s.uuid,
      isPrimary: s.isPrimary,
      characteristics:
          s.characteristics.map((c) {
            final charHandle = c.handle != 0 ? c.handle : ++_nextHandle;
            _charUuidByHandle[charHandle] = c.uuid.toLowerCase();
            return platform.PlatformCharacteristic(
              uuid: c.uuid,
              properties: c.properties,
              descriptors:
                  c.descriptors.map((d) {
                    final descHandle = d.handle != 0 ? d.handle : ++_nextHandle;
                    _descUuidByHandle[descHandle] = d.uuid.toLowerCase();
                    return platform.PlatformDescriptor(
                      uuid: d.uuid,
                      handle: descHandle,
                    );
                  }).toList(),
              handle: charHandle,
            );
          }).toList(),
      includedServices: s.includedServices.map(_withMintedHandles).toList(),
    );
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    int characteristicHandle,
  ) async {
    final uuid = _charUuidByHandle[characteristicHandle] ?? '';
    final value = characteristicValues[uuid];
    if (value == null) {
      throw StateError(
        'Characteristic not found: handle=$characteristicHandle',
      );
    }
    return value;
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    int characteristicHandle,
    Uint8List value,
    bool withResponse,
  ) async {
    final uuid = _charUuidByHandle[characteristicHandle] ?? '';
    writeCharacteristicCalls.add(
      WriteCharacteristicCall(
        deviceId: deviceId,
        characteristicUuid: uuid,
        value: value,
        withResponse: withResponse,
      ),
    );
  }

  @override
  Future<void> setNotification(
    String deviceId,
    int characteristicHandle,
    bool enable,
  ) async {
    final uuid = _charUuidByHandle[characteristicHandle] ?? '';
    setNotificationCalls.add(
      SetNotificationCall(
        deviceId: deviceId,
        characteristicUuid: uuid,
        enable: enable,
      ),
    );
  }

  @override
  Stream<platform.PlatformNotification> notificationStream(String deviceId) {
    return _notificationControllers[deviceId]?.stream ??
        Stream.error(StateError('Not connected'));
  }

  @override
  Future<Uint8List> readDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
  ) async {
    final uuid = _descUuidByHandle[descriptorHandle] ?? '';
    final value = descriptorValues[uuid];
    if (value == null) {
      throw StateError('Descriptor not found: handle=$descriptorHandle');
    }
    return value;
  }

  @override
  Future<void> writeDescriptor(
    String deviceId,
    int characteristicHandle,
    int descriptorHandle,
    Uint8List value,
  ) async {
    final uuid = _descUuidByHandle[descriptorHandle] ?? '';
    writeDescriptorCalls.add(
      WriteDescriptorCall(
        deviceId: deviceId,
        descriptorUuid: uuid,
        value: value,
      ),
    );
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    return mockMtu;
  }

  @override
  Future<int> getMaximumWriteLength(
    String deviceId, {
    required bool withResponse,
  }) async => withResponse ? 100 : 182;

  @override
  Future<int> readRssi(String deviceId) async {
    return mockRssi;
  }

  // Bonding operations - stub implementations
  @override
  Future<platform.PlatformBondState> getBondState(String deviceId) async =>
      platform.PlatformBondState.none;

  @override
  Stream<platform.PlatformBondState> bondStateStream(String deviceId) =>
      Stream.empty();

  @override
  Future<void> bond(String deviceId) async {}

  @override
  Future<void> removeBond(String deviceId) async {}

  @override
  Future<List<platform.PlatformDevice>> getBondedDevices() async => [];

  // PHY operations - stub implementations
  @override
  Future<({platform.PlatformPhy tx, platform.PlatformPhy rx})> getPhy(
    String deviceId,
  ) async => (tx: platform.PlatformPhy.le1m, rx: platform.PlatformPhy.le1m);

  @override
  Stream<({platform.PlatformPhy tx, platform.PlatformPhy rx})> phyStream(
    String deviceId,
  ) => Stream.empty();

  @override
  Future<void> requestPhy(
    String deviceId,
    platform.PlatformPhy? txPhy,
    platform.PlatformPhy? rxPhy,
  ) async {}

  // Connection parameters - stub implementations
  @override
  Future<platform.PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async => const platform.PlatformConnectionParameters(
    intervalMs: 30.0,
    latency: 0,
    timeoutMs: 4000,
  );

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    platform.PlatformConnectionParameters params,
  ) async {}

  // Server (Peripheral) operations - stub implementations
  @override
  Future<platform.PlatformLocalService> addService(
    platform.PlatformLocalService service,
  ) async => service;

  @override
  Future<void> removeService(String serviceUuid) async {}

  @override
  Future<void> startAdvertising(
    platform.PlatformAdvertiseConfig config,
  ) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> notifyCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {}

  @override
  Future<void> notifyCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {}

  @override
  Future<void> indicateCharacteristic(
    int characteristicHandle,
    Uint8List value,
  ) async {}

  @override
  Future<void> indicateCharacteristicTo(
    String centralId,
    int characteristicHandle,
    Uint8List value,
  ) async {}

  @override
  @override
  Stream<String> get serviceChanges => Stream.empty();

  @override
  Stream<platform.PlatformCentral> get centralConnections => Stream.empty();

  @override
  Stream<String> get centralDisconnections => Stream.empty();

  @override
  Stream<platform.PlatformReadRequest> get readRequests => Stream.empty();

  @override
  Stream<platform.PlatformWriteRequest> get writeRequests => Stream.empty();

  @override
  Future<void> respondToReadRequest(
    int requestId,
    platform.PlatformGattStatus status,
    Uint8List? value,
  ) async {}

  @override
  Future<void> respondToWriteRequest(
    int requestId,
    platform.PlatformGattStatus status,
  ) async {}

  @override
  Future<void> closeServer() async {}

  // Structured logging - stub implementations (I307)
  @override
  Stream<platform.PlatformLogEvent> get logEvents => Stream.empty();

  @override
  Future<void> setLogLevel(platform.PlatformLogLevel level) async {}

  // Helper to emit a notification
  void emitNotification(
    String deviceId,
    String characteristicUuid,
    Uint8List value,
  ) {
    _notificationControllers[deviceId]?.add(
      platform.PlatformNotification(
        deviceId: deviceId,
        characteristicUuid: characteristicUuid,
        value: value,
      ),
    );
  }
}

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

class WriteDescriptorCall {
  final String deviceId;
  final String descriptorUuid;
  final Uint8List value;

  WriteDescriptorCall({
    required this.deviceId,
    required this.descriptorUuid,
    required this.value,
  });
}

class SetNotificationCall {
  final String deviceId;
  final String characteristicUuid;
  final bool enable;

  SetNotificationCall({
    required this.deviceId,
    required this.characteristicUuid,
    required this.enable,
  });
}

void main() {
  group('BlueyConnection', () {
    late MockBlueyPlatform mockPlatform;
    late BlueyConnection connection;
    final deviceId = UUID('00000000-0000-0000-0000-aabbccddeeff');

    setUp(() async {
      mockPlatform = MockBlueyPlatform();
      await mockPlatform.connect(
        deviceId.toString(),
        const platform.PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
      connection = BlueyConnection(
        platformInstance: mockPlatform,
        connectionId: deviceId.toString(),
        deviceId: deviceId,
        logger: BlueyLogger(),
      );
    });

    tearDown(() async {
      await connection.disconnect();
    });

    group('Service Discovery', () {
      test('services returns discovered services', () async {
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb', // Heart Rate
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
          platform.PlatformService(
            uuid: '0000180f-0000-1000-8000-00805f9b34fb', // Battery
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ];

        final services = await connection.services();

        expect(services, hasLength(2));
        expect(services[0].uuid, equals(UUID.short(0x180D)));
        expect(services[1].uuid, equals(UUID.short(0x180F)));
      });

      test('service() finds service by UUID', () async {
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ];

        // Trigger service discovery
        await connection.services();

        final svc = connection.service(UUID.short(0x180D));
        expect(svc.uuid, equals(UUID.short(0x180D)));
      });

      test(
        'service() throws ServiceNotFoundException when not found',
        () async {
          mockPlatform.mockServices = [];
          await connection.services();

          expect(
            () => connection.service(UUID.short(0x180D)),
            throwsA(isA<ServiceNotFoundException>()),
          );
        },
      );

      test('services caches results after first discovery', () async {
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ];

        // First call discovers
        await connection.services();
        // Second call uses cache
        await connection.services(cache: true);

        // Verify cached result is correct
        expect(await connection.services(cache: true), hasLength(1));
      });
    });

    group('Characteristic Read', () {
      test('read() returns characteristic value', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
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
        ];
        mockPlatform.characteristicValues[charUuid] = Uint8List.fromList([
          0x00,
          60,
        ]); // Heart rate 60 bpm

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        final value = await char.read();

        expect(value, equals(Uint8List.fromList([0x00, 60])));
      });

      test(
        'read() throws OperationNotSupportedException when not readable',
        () async {
          final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
          mockPlatform.mockServices = [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: charUuid,
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: false, // Not readable
                    canWrite: true,
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
          ];

          await connection.services();
          final svc = connection.service(UUID.short(0x180D));
          final char = svc.characteristic(UUID(charUuid));

          expect(
            () => char.read(),
            throwsA(isA<OperationNotSupportedException>()),
          );
        },
      );
    });

    group('Characteristic Write', () {
      test('write() sends value to platform', () async {
        final charUuid = '00002a39-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: true,
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
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        await char.write(Uint8List.fromList([0x01]));

        expect(mockPlatform.writeCharacteristicCalls, hasLength(1));
        expect(
          mockPlatform.writeCharacteristicCalls[0].value,
          equals(Uint8List.fromList([0x01])),
        );
        expect(mockPlatform.writeCharacteristicCalls[0].withResponse, isTrue);
      });

      test('write() without response', () async {
        final charUuid = '00002a39-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: true,
                  canNotify: false,
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        await char.write(Uint8List.fromList([0x01]), withResponse: false);

        expect(mockPlatform.writeCharacteristicCalls, hasLength(1));
        expect(mockPlatform.writeCharacteristicCalls[0].withResponse, isFalse);
      });

      test(
        'write() throws OperationNotSupportedException when not writable',
        () async {
          final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
          mockPlatform.mockServices = [
            platform.PlatformService(
              uuid: '0000180d-0000-1000-8000-00805f9b34fb',
              isPrimary: true,
              characteristics: [
                platform.PlatformCharacteristic(
                  uuid: charUuid,
                  properties: const platform.PlatformCharacteristicProperties(
                    canRead: true,
                    canWrite: false, // Not writable
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
          ];

          await connection.services();
          final svc = connection.service(UUID.short(0x180D));
          final char = svc.characteristic(UUID(charUuid));

          expect(
            () => char.write(Uint8List.fromList([0x01])),
            throwsA(isA<OperationNotSupportedException>()),
          );
        },
      );
    });

    group('Notifications', () {
      test('notifications stream receives values', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
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
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        final values = <Uint8List>[];
        final subscription = char.notifications.listen(values.add);

        // Give time for subscription to be set up
        await Future.delayed(Duration.zero);

        // Emit notifications
        mockPlatform.emitNotification(
          deviceId.toString(),
          charUuid,
          Uint8List.fromList([0x00, 65]),
        );
        mockPlatform.emitNotification(
          deviceId.toString(),
          charUuid,
          Uint8List.fromList([0x00, 70]),
        );

        await Future.delayed(Duration(milliseconds: 10));
        await subscription.cancel();

        expect(values, hasLength(2));
        expect(values[0], equals(Uint8List.fromList([0x00, 65])));
        expect(values[1], equals(Uint8List.fromList([0x00, 70])));
      });

      test('subscribing enables notifications on platform', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
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
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        final subscription = char.notifications.listen((_) {});
        await Future.delayed(Duration.zero);

        expect(mockPlatform.setNotificationCalls, hasLength(1));
        expect(mockPlatform.setNotificationCalls[0].enable, isTrue);

        await subscription.cancel();
      });

      test('notifications throws when not notifiable', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
                  canRead: true,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: false, // Not notifiable
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));

        expect(
          () => char.notifications,
          throwsA(isA<OperationNotSupportedException>()),
        );
      });
    });

    group('MTU', () {
      test('requestMtu returns negotiated MTU from platform', () async {
        mockPlatform.mockMtu = 256;

        final mtu = await connection.android!.requestMtu(
          Mtu(512, capabilities: platform.Capabilities.android),
        );

        expect(mtu, equals(Mtu.fromPlatform(256)));
        expect(connection.android?.mtu, equals(Mtu.fromPlatform(256)));
      });
    });

    group('RSSI', () {
      test('readRssi returns value from platform', () async {
        mockPlatform.mockRssi = -75;

        final rssi = await connection.readRssi();

        expect(rssi, equals(-75));
      });
    });

    group('Descriptors', () {
      test('descriptor read returns value', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        final descUuid = '00002902-0000-1000-8000-00805f9b34fb'; // CCCD
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
                  canRead: true,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [
                  platform.PlatformDescriptor(uuid: descUuid, handle: 0),
                ],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ];
        mockPlatform.descriptorValues[descUuid] = Uint8List.fromList([
          0x01,
          0x00,
        ]);

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));
        final desc = char.descriptor(UUID(descUuid));

        final value = await desc.read();

        expect(value, equals(Uint8List.fromList([0x01, 0x00])));
      });

      test('descriptor write sends value to platform', () async {
        final charUuid = '00002a37-0000-1000-8000-00805f9b34fb';
        final descUuid = '00002902-0000-1000-8000-00805f9b34fb';
        mockPlatform.mockServices = [
          platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: charUuid,
                properties: const platform.PlatformCharacteristicProperties(
                  canRead: true,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [
                  platform.PlatformDescriptor(uuid: descUuid, handle: 0),
                ],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ];

        await connection.services();
        final svc = connection.service(UUID.short(0x180D));
        final char = svc.characteristic(UUID(charUuid));
        final desc = char.descriptor(UUID(descUuid));

        await desc.write(Uint8List.fromList([0x01, 0x00]));

        expect(mockPlatform.writeDescriptorCalls, hasLength(1));
        expect(
          mockPlatform.writeDescriptorCalls[0].value,
          equals(Uint8List.fromList([0x01, 0x00])),
        );
      });
    });
  });
}

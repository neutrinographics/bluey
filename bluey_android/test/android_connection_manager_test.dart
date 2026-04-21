import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey_android/src/android_connection_manager.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late AndroidConnectionManager connectionManager;

  setUpAll(() {
    registerFallbackValue(ConnectConfigDto());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    connectionManager = AndroidConnectionManager(mockHostApi);
  });

  group('AndroidConnectionManager', () {
    group('connect', () {
      test('calls hostApi.connect and returns connection ID', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: 5000, mtu: 512);
        final result = await connectionManager.connect('device-1', config);

        expect(result, equals('conn-123'));

        final captured =
            verify(() => mockHostApi.connect('device-1', captureAny()))
                .captured
                .single as ConnectConfigDto;

        expect(captured.timeoutMs, equals(5000));
        expect(captured.mtu, equals(512));
      });

      test('creates per-device stream controllers', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        // Should be able to get streams without error
        final stateStream =
            connectionManager.connectionStateStream('device-1');
        final notifStream = connectionManager.notificationStream('device-1');

        expect(stateStream, isA<Stream<PlatformConnectionState>>());
        expect(notifStream, isA<Stream<PlatformNotification>>());
      });
    });

    group('disconnect', () {
      test('calls hostApi.disconnect and cleans up per-device streams',
          () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');
        when(() => mockHostApi.disconnect(any())).thenAnswer((_) async {});

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        await connectionManager.disconnect('device-1');

        verify(() => mockHostApi.disconnect('device-1')).called(1);

        // After disconnect, stream should error since controllers are removed
        final stateStream =
            connectionManager.connectionStateStream('device-1');
        expect(stateStream, emitsError(isA<StateError>()));
      });
    });

    group('onConnectionStateChanged', () {
      test('routes to correct device stream', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        final stateStream =
            connectionManager.connectionStateStream('device-1');
        final future = stateStream.first;

        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device-1',
            state: ConnectionStateDto.connected,
          ),
        );

        final state = await future;
        expect(state, equals(PlatformConnectionState.connected));
      });

      test('ignores events for unknown devices', () {
        // Should not throw
        expect(
          () => connectionManager.onConnectionStateChanged(
            ConnectionStateEventDto(
              deviceId: 'unknown-device',
              state: ConnectionStateDto.connected,
            ),
          ),
          returnsNormally,
        );
      });
    });

    group('onNotification', () {
      test('routes to correct device stream', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        final notifStream = connectionManager.notificationStream('device-1');
        final future = notifStream.first;

        final data = Uint8List.fromList([0x01, 0x02, 0x03]);
        connectionManager.onNotification(
          NotificationEventDto(
            deviceId: 'device-1',
            characteristicUuid: '2A37',
            value: data,
          ),
        );

        final notification = await future;
        expect(notification.deviceId, equals('device-1'));
        expect(notification.characteristicUuid, equals('2A37'));
        expect(notification.value, equals(data));
      });
    });

    group('discoverServices', () {
      test('maps DTOs correctly with nested service, characteristic, descriptor',
          () async {
        final serviceDtos = [
          ServiceDto(
            uuid: '180D',
            isPrimary: true,
            characteristics: [
              CharacteristicDto(
                uuid: '2A37',
                properties: CharacteristicPropertiesDto(
                  canRead: true,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [
                  DescriptorDto(uuid: '2902'),
                ],
              ),
            ],
            includedServices: [],
          ),
        ];

        when(() => mockHostApi.discoverServices(any()))
            .thenAnswer((_) async => serviceDtos);

        final services = await connectionManager.discoverServices('device-1');

        expect(services, hasLength(1));
        expect(services[0].uuid, equals('180D'));
        expect(services[0].isPrimary, isTrue);
        expect(services[0].characteristics, hasLength(1));
        expect(services[0].characteristics[0].uuid, equals('2A37'));
        expect(services[0].characteristics[0].properties.canRead, isTrue);
        expect(services[0].characteristics[0].properties.canNotify, isTrue);
        expect(services[0].characteristics[0].properties.canWrite, isFalse);
        expect(services[0].characteristics[0].descriptors, hasLength(1));
        expect(
            services[0].characteristics[0].descriptors[0].uuid, equals('2902'));
        expect(services[0].includedServices, isEmpty);
      });
    });

    group('readCharacteristic', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x42]);
        when(() => mockHostApi.readCharacteristic(any(), any()))
            .thenAnswer((_) async => data);

        final result =
            await connectionManager.readCharacteristic('device-1', '2A37');

        expect(result, equals(data));
        verify(() => mockHostApi.readCharacteristic('device-1', '2A37'))
            .called(1);
      });
    });

    group('writeCharacteristic', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x01]);
        when(() => mockHostApi.writeCharacteristic(
              any(), any(), any(), any(),
            )).thenAnswer((_) async {});

        await connectionManager.writeCharacteristic(
            'device-1', '2A37', data, true);

        verify(() =>
                mockHostApi.writeCharacteristic('device-1', '2A37', data, true))
            .called(1);
      });
    });

    group('setNotification', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.setNotification('device-1', '2A37', true))
            .thenAnswer((_) async {});

        await connectionManager.setNotification('device-1', '2A37', true);

        verify(() => mockHostApi.setNotification('device-1', '2A37', true))
            .called(1);
      });
    });

    group('readDescriptor', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x00, 0x01]);
        when(() => mockHostApi.readDescriptor(any(), any()))
            .thenAnswer((_) async => data);

        final result =
            await connectionManager.readDescriptor('device-1', '2902');

        expect(result, equals(data));
        verify(() => mockHostApi.readDescriptor('device-1', '2902')).called(1);
      });
    });

    group('writeDescriptor', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x01, 0x00]);
        when(() => mockHostApi.writeDescriptor(any(), any(), any()))
            .thenAnswer((_) async {});

        await connectionManager.writeDescriptor('device-1', '2902', data);

        verify(() => mockHostApi.writeDescriptor('device-1', '2902', data))
            .called(1);
      });
    });

    group('requestMtu', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.requestMtu('device-1', 517))
            .thenAnswer((_) async => 517);

        final result = await connectionManager.requestMtu('device-1', 517);

        expect(result, equals(517));
        verify(() => mockHostApi.requestMtu('device-1', 517)).called(1);
      });
    });

    group('readRssi', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.readRssi(any())).thenAnswer((_) async => -55);

        final result = await connectionManager.readRssi('device-1');

        expect(result, equals(-55));
        verify(() => mockHostApi.readRssi('device-1')).called(1);
      });
    });

    group('bonding stubs', () {
      test('getBondState returns none', () async {
        final state = await connectionManager.getBondState('device-1');
        expect(state, equals(PlatformBondState.none));
      });

      test('bondStateStream returns empty stream', () {
        final stream = connectionManager.bondStateStream('device-1');
        expect(stream, emitsDone);
      });

      test('bond is a no-op', () async {
        await connectionManager.bond('device-1');
        // No exception means success
      });

      test('removeBond is a no-op', () async {
        await connectionManager.removeBond('device-1');
        // No exception means success
      });

      test('getBondedDevices returns empty list', () async {
        final devices = await connectionManager.getBondedDevices();
        expect(devices, isEmpty);
      });
    });

    group('PHY stubs', () {
      test('getPhy returns le1m for both tx and rx', () async {
        final phy = await connectionManager.getPhy('device-1');
        expect(phy.tx, equals(PlatformPhy.le1m));
        expect(phy.rx, equals(PlatformPhy.le1m));
      });

      test('phyStream returns empty stream', () {
        final stream = connectionManager.phyStream('device-1');
        expect(stream, emitsDone);
      });

      test('requestPhy is a no-op', () async {
        await connectionManager.requestPhy(
            'device-1', PlatformPhy.le2m, PlatformPhy.le2m);
        // No exception means success
      });
    });

    group('connection parameters stubs', () {
      test('getConnectionParameters returns defaults', () async {
        final params =
            await connectionManager.getConnectionParameters('device-1');
        expect(params.intervalMs, equals(30));
        expect(params.latency, equals(0));
        expect(params.timeoutMs, equals(5000));
      });

      test('requestConnectionParameters is a no-op', () async {
        await connectionManager.requestConnectionParameters(
          'device-1',
          const PlatformConnectionParameters(
            intervalMs: 15,
            latency: 0,
            timeoutMs: 2000,
          ),
        );
        // No exception means success
      });
    });

    group('onMtuChanged', () {
      test('does not throw for known device', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        expect(
          () => connectionManager.onMtuChanged(
            MtuChangedEventDto(deviceId: 'device-1', mtu: 512),
          ),
          returnsNormally,
        );
      });

      test('does not throw for unknown device', () {
        expect(
          () => connectionManager.onMtuChanged(
            MtuChangedEventDto(deviceId: 'unknown', mtu: 512),
          ),
          returnsNormally,
        );
      });
    });

    group('connectionStateStream', () {
      test('returns error stream for unconnected device', () {
        final stream =
            connectionManager.connectionStateStream('unknown-device');
        expect(stream, emitsError(isA<StateError>()));
      });
    });

    group('notificationStream', () {
      test('returns error stream for unconnected device', () {
        final stream = connectionManager.notificationStream('unknown-device');
        expect(stream, emitsError(isA<StateError>()));
      });
    });

    group('error translation', () {
      test(
        'writeCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Write timed out'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')),
          );
        },
      );

      test(
        'writeCharacteristic rethrows non-timeout PlatformException unchanged',
        () async {
          final original = PlatformException(
            code: 'IllegalStateException',
            message: 'Failed to write characteristic',
          );
          when(() => mockHostApi.writeCharacteristic(
                any(),
                any(),
                any(),
                any(),
              )).thenThrow(original);

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(predicate<PlatformException>(
              (e) => e.code == 'IllegalStateException',
            )),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Read timed out'),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 'char-uuid'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'readCharacteristic')),
          );
        },
      );

      test(
        'discoverServices translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.discoverServices(any())).thenThrow(
            PlatformException(
                code: 'gatt-timeout', message: 'Discovery timed out'),
          );

          expect(
            () => connectionManager.discoverServices('device-1'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'discoverServices')),
          );
        },
      );

      test(
        'writeCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(), any(), any(), any(),
              )).thenThrow(
            PlatformException(code: 'gatt-disconnected', message: 'link lost'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(code: 'gatt-disconnected', message: 'link lost'),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 'char-uuid'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readCharacteristic')),
          );
        },
      );

      test(
        'all wrapped methods translate gatt-disconnected with correct operation name',
        () async {
          final disconnect = PlatformException(
            code: 'gatt-disconnected',
            message: 'link lost',
          );

          when(() => mockHostApi.setNotification(any(), any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.setNotification('d', 'c', true),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'setNotification')),
          );

          when(() => mockHostApi.readDescriptor(any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readDescriptor('d', 'desc'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readDescriptor')),
          );

          when(() => mockHostApi.writeDescriptor(any(), any(), any()))
              .thenThrow(disconnect);
          await expectLater(
            () => connectionManager.writeDescriptor(
              'd', 'desc', Uint8List.fromList([0x01]),
            ),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'writeDescriptor')),
          );

          when(() => mockHostApi.requestMtu(any(), any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.requestMtu('d', 200),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'requestMtu')),
          );

          when(() => mockHostApi.readRssi(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readRssi('d'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'readRssi')),
          );

          when(() => mockHostApi.discoverServices(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.discoverServices('d'),
            throwsA(isA<GattOperationDisconnectedException>()
                .having((e) => e.operation, 'operation', 'discoverServices')),
          );
        },
      );

      test(
        'all wrapped methods translate gatt-timeout with correct operation name',
        () async {
          // Verify each remaining wrapped method (beyond the explicitly
          // tested writeCharacteristic / readCharacteristic / discoverServices)
          // passes its own name as the operation. Catches copy-paste typos
          // in the operation-name string passed to _translateGattPlatformError.
          final timeout = PlatformException(
            code: 'gatt-timeout',
            message: 'timeout',
          );

          // setNotification
          when(() => mockHostApi.setNotification(any(), any(), any()))
              .thenThrow(timeout);
          await expectLater(
            () => connectionManager.setNotification('d', 'c', true),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'setNotification')),
          );

          // readDescriptor
          when(() => mockHostApi.readDescriptor(any(), any()))
              .thenThrow(timeout);
          await expectLater(
            () => connectionManager.readDescriptor('d', 'desc'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'readDescriptor')),
          );

          // writeDescriptor
          when(() => mockHostApi.writeDescriptor(any(), any(), any()))
              .thenThrow(timeout);
          await expectLater(
            () => connectionManager.writeDescriptor(
              'd',
              'desc',
              Uint8List.fromList([0x01]),
            ),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'writeDescriptor')),
          );

          // requestMtu
          when(() => mockHostApi.requestMtu(any(), any())).thenThrow(timeout);
          await expectLater(
            () => connectionManager.requestMtu('d', 200),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'requestMtu')),
          );

          // readRssi
          when(() => mockHostApi.readRssi(any())).thenThrow(timeout);
          await expectLater(
            () => connectionManager.readRssi('d'),
            throwsA(isA<GattOperationTimeoutException>()
                .having((e) => e.operation, 'operation', 'readRssi')),
          );
        },
      );
    });
  });
}

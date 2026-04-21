import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey_ios/src/ios_connection_manager.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late IosConnectionManager connectionManager;

  setUpAll(() {
    registerFallbackValue(ConnectConfigDto());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    connectionManager = IosConnectionManager(mockHostApi);
  });

  group('IosConnectionManager', () {
    group('connect', () {
      test('calls hostApi.connect and returns connection ID', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = const PlatformConnectConfig(
          timeoutMs: 5000,
          mtu: 512,
        );

        final result = await connectionManager.connect('device-1', config);

        expect(result, equals('conn-123'));

        final captured = verify(
          () => mockHostApi.connect('device-1', captureAny()),
        ).captured.single as ConnectConfigDto;

        expect(captured.timeoutMs, equals(5000));
        expect(captured.mtu, equals(512));
      });

      test('creates per-device connection state stream', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);

        final stream = connectionManager.connectionStateStream('device-1');
        expect(stream, isA<Stream<PlatformConnectionState>>());
      });

      test('creates per-device notification stream', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);

        final stream = connectionManager.notificationStream('device-1');
        expect(stream, isA<Stream<PlatformNotification>>());
      });
    });

    group('disconnect', () {
      test('calls hostApi.disconnect and cleans up streams', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-123');
        when(() => mockHostApi.disconnect(any())).thenAnswer((_) async {});

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);
        await connectionManager.disconnect('device-1');

        verify(() => mockHostApi.disconnect('device-1')).called(1);

        // After disconnect, streams should error (device not connected)
        final stateStream =
            connectionManager.connectionStateStream('device-1');
        expect(stateStream, emitsError(isA<StateError>()));

        final notifStream = connectionManager.notificationStream('device-1');
        expect(notifStream, emitsError(isA<StateError>()));
      });
    });

    group('connectionStateStream', () {
      test('returns error stream for unknown device', () {
        final stream = connectionManager.connectionStateStream('unknown');
        expect(stream, emitsError(isA<StateError>()));
      });
    });

    group('notificationStream', () {
      test('returns error stream for unknown device', () {
        final stream = connectionManager.notificationStream('unknown');
        expect(stream, emitsError(isA<StateError>()));
      });
    });

    group('onConnectionStateChanged', () {
      test('routes event to correct device stream', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-1');

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);

        final stream = connectionManager.connectionStateStream('device-1');
        final future = stream.first;

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
        // Should not throw when no matching controller exists
        expect(
          () => connectionManager.onConnectionStateChanged(
            ConnectionStateEventDto(
              deviceId: 'unknown',
              state: ConnectionStateDto.connected,
            ),
          ),
          returnsNormally,
        );
      });

      test('maps all connection state values correctly', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-1');

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);

        final states = <PlatformConnectionState>[];
        final stream = connectionManager.connectionStateStream('device-1');
        final sub = stream.listen(states.add);

        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device-1',
            state: ConnectionStateDto.connecting,
          ),
        );
        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device-1',
            state: ConnectionStateDto.connected,
          ),
        );
        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device-1',
            state: ConnectionStateDto.disconnecting,
          ),
        );
        connectionManager.onConnectionStateChanged(
          ConnectionStateEventDto(
            deviceId: 'device-1',
            state: ConnectionStateDto.disconnected,
          ),
        );

        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(states, equals([
          PlatformConnectionState.connecting,
          PlatformConnectionState.connected,
          PlatformConnectionState.disconnecting,
          PlatformConnectionState.disconnected,
        ]));
      });
    });

    group('onNotification', () {
      test('routes notification with expanded UUID', () async {
        when(() => mockHostApi.connect(any(), any()))
            .thenAnswer((_) async => 'conn-1');

        final config = const PlatformConnectConfig(
          timeoutMs: null,
          mtu: null,
        );

        await connectionManager.connect('device-1', config);

        final stream = connectionManager.notificationStream('device-1');
        final future = stream.first;

        final value = Uint8List.fromList([0x01, 0x02, 0x03]);

        connectionManager.onNotification(
          NotificationEventDto(
            deviceId: 'device-1',
            characteristicUuid: '2A37',
            value: value,
          ),
        );

        final notification = await future;
        expect(notification.deviceId, equals('device-1'));
        expect(
          notification.characteristicUuid,
          equals('00002a37-0000-1000-8000-00805f9b34fb'),
        );
        expect(notification.value, equals(value));
      });

      test('ignores notifications for unknown devices', () {
        expect(
          () => connectionManager.onNotification(
            NotificationEventDto(
              deviceId: 'unknown',
              characteristicUuid: '2A37',
              value: Uint8List(0),
            ),
          ),
          returnsNormally,
        );
      });
    });

    group('onMtuChanged', () {
      test('does not throw', () {
        expect(
          () => connectionManager.onMtuChanged(
            MtuChangedEventDto(deviceId: 'device-1', mtu: 512),
          ),
          returnsNormally,
        );
      });
    });

    group('discoverServices', () {
      test('maps DTOs with expanded UUIDs', () async {
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

        final services =
            await connectionManager.discoverServices('device-1');

        expect(services.length, equals(1));

        final service = services.first;
        expect(
          service.uuid,
          equals('0000180d-0000-1000-8000-00805f9b34fb'),
        );
        expect(service.isPrimary, isTrue);

        final characteristic = service.characteristics.first;
        expect(
          characteristic.uuid,
          equals('00002a37-0000-1000-8000-00805f9b34fb'),
        );
        expect(characteristic.properties.canRead, isTrue);
        expect(characteristic.properties.canNotify, isTrue);
        expect(characteristic.properties.canWrite, isFalse);

        final descriptor = characteristic.descriptors.first;
        expect(
          descriptor.uuid,
          equals('00002902-0000-1000-8000-00805f9b34fb'),
        );
      });

      test('maps nested included services with expanded UUIDs', () async {
        final serviceDtos = [
          ServiceDto(
            uuid: '1800',
            isPrimary: true,
            characteristics: [],
            includedServices: [
              ServiceDto(
                uuid: '1801',
                isPrimary: false,
                characteristics: [],
                includedServices: [],
              ),
            ],
          ),
        ];

        when(() => mockHostApi.discoverServices(any()))
            .thenAnswer((_) async => serviceDtos);

        final services =
            await connectionManager.discoverServices('device-1');

        final included = services.first.includedServices.first;
        expect(
          included.uuid,
          equals('00001801-0000-1000-8000-00805f9b34fb'),
        );
        expect(included.isPrimary, isFalse);
      });
    });

    group('readCharacteristic', () {
      test('delegates to hostApi', () async {
        final expected = Uint8List.fromList([0x42]);
        when(() => mockHostApi.readCharacteristic(any(), any()))
            .thenAnswer((_) async => expected);

        final result = await connectionManager.readCharacteristic(
          'device-1',
          'char-uuid',
        );

        expect(result, equals(expected));
        verify(
          () => mockHostApi.readCharacteristic('device-1', 'char-uuid'),
        ).called(1);
      });
    });

    group('writeCharacteristic', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.writeCharacteristic(any(), any(), any(), any()))
            .thenAnswer((_) async {});

        final value = Uint8List.fromList([0x01, 0x02]);
        await connectionManager.writeCharacteristic(
          'device-1',
          'char-uuid',
          value,
          true,
        );

        verify(
          () => mockHostApi.writeCharacteristic(
            'device-1',
            'char-uuid',
            value,
            true,
          ),
        ).called(1);
      });
    });

    group('setNotification', () {
      test('delegates to hostApi', () async {
        when(
          () => mockHostApi.setNotification('device-1', 'char-uuid', true),
        ).thenAnswer((_) async {});

        await connectionManager.setNotification(
          'device-1',
          'char-uuid',
          true,
        );

        verify(
          () => mockHostApi.setNotification('device-1', 'char-uuid', true),
        ).called(1);
      });
    });

    group('readDescriptor', () {
      test('delegates to hostApi', () async {
        final expected = Uint8List.fromList([0x00, 0x01]);
        when(() => mockHostApi.readDescriptor(any(), any()))
            .thenAnswer((_) async => expected);

        final result = await connectionManager.readDescriptor(
          'device-1',
          'desc-uuid',
        );

        expect(result, equals(expected));
        verify(
          () => mockHostApi.readDescriptor('device-1', 'desc-uuid'),
        ).called(1);
      });
    });

    group('writeDescriptor', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.writeDescriptor(any(), any(), any()))
            .thenAnswer((_) async {});

        final value = Uint8List.fromList([0x01]);
        await connectionManager.writeDescriptor(
          'device-1',
          'desc-uuid',
          value,
        );

        verify(
          () => mockHostApi.writeDescriptor('device-1', 'desc-uuid', value),
        ).called(1);
      });
    });

    group('readRssi', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.readRssi('device-1'))
            .thenAnswer((_) async => -65);

        final result = await connectionManager.readRssi('device-1');

        expect(result, equals(-65));
        verify(() => mockHostApi.readRssi('device-1')).called(1);
      });
    });

    group('unsupported operations', () {
      test('requestMtu throws UnsupportedError', () {
        expect(
          () => connectionManager.requestMtu('device-1', 512),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('removeBond throws UnsupportedError', () {
        expect(
          () => connectionManager.removeBond('device-1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getPhy throws UnsupportedError', () {
        expect(
          () => connectionManager.getPhy('device-1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestPhy throws UnsupportedError', () {
        expect(
          () => connectionManager.requestPhy(
            'device-1',
            PlatformPhy.le2m,
            null,
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getConnectionParameters throws UnsupportedError', () {
        expect(
          () => connectionManager.getConnectionParameters('device-1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestConnectionParameters throws UnsupportedError', () {
        expect(
          () => connectionManager.requestConnectionParameters(
            'device-1',
            const PlatformConnectionParameters(
              intervalMs: 15,
              latency: 0,
              timeoutMs: 5000,
            ),
          ),
          throwsA(isA<UnsupportedError>()),
        );
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

      test('bond completes without error (no-op)', () async {
        await connectionManager.bond('device-1');
      });

      test('getBondedDevices returns empty list', () async {
        final devices = await connectionManager.getBondedDevices();
        expect(devices, isEmpty);
      });
    });

    group('PHY stubs', () {
      test('phyStream returns empty stream', () {
        final stream = connectionManager.phyStream('device-1');
        expect(stream, emitsDone);
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
          // 'notFound' is a real iOS code: Pigeon's wrapError renders bare
          // Swift enum errors as PlatformException(code: <case>, message: <type>).
          final original = PlatformException(
            code: 'notFound',
            message: 'BlueyError',
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
              (e) => e.code == 'notFound',
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
        'writeCharacteristic translates PlatformException(gatt-status-failed) to GattOperationStatusFailedException',
        () async {
          when(() => mockHostApi.writeCharacteristic(
                any(), any(), any(), any(),
              )).thenThrow(
            PlatformException(
              code: 'gatt-status-failed',
              message: 'Write failed with status: 1',
              details: 1,
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              'char-uuid',
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(isA<GattOperationStatusFailedException>()
                .having((e) => e.operation, 'operation', 'writeCharacteristic')
                .having((e) => e.status, 'status', 1)),
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

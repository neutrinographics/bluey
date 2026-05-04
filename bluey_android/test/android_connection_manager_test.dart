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
        when(
          () => mockHostApi.connect(any(), any()),
        ).thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: 5000, mtu: 512);
        final result = await connectionManager.connect('device-1', config);

        expect(result, equals('conn-123'));

        final captured =
            verify(
                  () => mockHostApi.connect('device-1', captureAny()),
                ).captured.single
                as ConnectConfigDto;

        expect(captured.timeoutMs, equals(5000));
        expect(captured.mtu, equals(512));
      });

      test('creates per-device stream controllers', () async {
        when(
          () => mockHostApi.connect(any(), any()),
        ).thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        // Should be able to get streams without error
        final stateStream = connectionManager.connectionStateStream('device-1');
        final notifStream = connectionManager.notificationStream('device-1');

        expect(stateStream, isA<Stream<PlatformConnectionState>>());
        expect(notifStream, isA<Stream<PlatformNotification>>());
      });
    });

    group('disconnect', () {
      test(
        'calls hostApi.disconnect and cleans up per-device streams',
        () async {
          when(
            () => mockHostApi.connect(any(), any()),
          ).thenAnswer((_) async => 'conn-123');
          when(() => mockHostApi.disconnect(any())).thenAnswer((_) async {});

          final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
          await connectionManager.connect('device-1', config);

          await connectionManager.disconnect('device-1');

          verify(() => mockHostApi.disconnect('device-1')).called(1);

          // After disconnect, stream should error since controllers are removed
          final stateStream = connectionManager.connectionStateStream(
            'device-1',
          );
          expect(stateStream, emitsError(isA<StateError>()));
        },
      );
    });

    group('onConnectionStateChanged', () {
      test('routes to correct device stream', () async {
        when(
          () => mockHostApi.connect(any(), any()),
        ).thenAnswer((_) async => 'conn-123');

        final config = PlatformConnectConfig(timeoutMs: null, mtu: null);
        await connectionManager.connect('device-1', config);

        final stateStream = connectionManager.connectionStateStream('device-1');
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
        when(
          () => mockHostApi.connect(any(), any()),
        ).thenAnswer((_) async => 'conn-123');

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
      test(
        'maps DTOs correctly with nested service, characteristic, descriptor',
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
                  descriptors: [DescriptorDto(uuid: '2902', handle: 99)],
                  handle: 100,
                ),
              ],
              includedServices: [],
            ),
          ];

          when(
            () => mockHostApi.discoverServices(any()),
          ).thenAnswer((_) async => serviceDtos);

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
            services[0].characteristics[0].descriptors[0].uuid,
            equals('2902'),
          );
          expect(services[0].includedServices, isEmpty);
        },
      );
    });

    group('readCharacteristic', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x42]);
        when(
          () => mockHostApi.readCharacteristic(any(), any()),
        ).thenAnswer((_) async => data);

        final result = await connectionManager.readCharacteristic(
          'device-1',
          100,
        );

        expect(result, equals(data));
        verify(() => mockHostApi.readCharacteristic('device-1', 100)).called(1);
      });
    });

    group('writeCharacteristic', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x01]);
        when(
          () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
        ).thenAnswer((_) async {});

        await connectionManager.writeCharacteristic(
          'device-1',
          100,
          data,
          true,
        );

        verify(
          () => mockHostApi.writeCharacteristic('device-1', 100, data, true),
        ).called(1);
      });
    });

    group('setNotification', () {
      test('delegates to hostApi', () async {
        when(
          () => mockHostApi.setNotification('device-1', 100, true),
        ).thenAnswer((_) async {});

        await connectionManager.setNotification('device-1', 100, true);

        verify(
          () => mockHostApi.setNotification('device-1', 100, true),
        ).called(1);
      });
    });

    group('readDescriptor', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x00, 0x01]);
        when(
          () => mockHostApi.readDescriptor(any(), any(), any()),
        ).thenAnswer((_) async => data);

        final result = await connectionManager.readDescriptor(
          'device-1',
          100,
          99,
        );

        expect(result, equals(data));
        verify(() => mockHostApi.readDescriptor('device-1', 100, 99)).called(1);
      });
    });

    group('writeDescriptor', () {
      test('delegates to hostApi', () async {
        final data = Uint8List.fromList([0x01, 0x00]);
        when(
          () => mockHostApi.writeDescriptor(any(), any(), any(), any()),
        ).thenAnswer((_) async {});

        await connectionManager.writeDescriptor('device-1', 100, 99, data);

        verify(
          () => mockHostApi.writeDescriptor('device-1', 100, 99, data),
        ).called(1);
      });
    });

    group('requestMtu', () {
      test('delegates to hostApi', () async {
        when(
          () => mockHostApi.requestMtu('device-1', 517),
        ).thenAnswer((_) async => 517);

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

    // Bonding / PHY / connection-parameter stubs are exercised by the
    // 'unimplemented stubs (I035 Stage A)' group at the bottom of this
    // file — they all throw UnimplementedError until Stage B wires the
    // Pigeon plumbing through.

    group('onMtuChanged', () {
      test('does not throw for known device', () async {
        when(
          () => mockHostApi.connect(any(), any()),
        ).thenAnswer((_) async => 'conn-123');

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
        final stream = connectionManager.connectionStateStream(
          'unknown-device',
        );
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
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(code: 'gatt-timeout', message: 'Write timed out'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'writeCharacteristic',
              ),
            ),
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
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(original);

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              predicate<PlatformException>(
                (e) => e.code == 'IllegalStateException',
              ),
            ),
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
            () => connectionManager.readCharacteristic('device-1', 42),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'readCharacteristic',
              ),
            ),
          );
        },
      );

      test(
        'discoverServices translates PlatformException(gatt-timeout) to GattOperationTimeoutException',
        () async {
          when(() => mockHostApi.discoverServices(any())).thenThrow(
            PlatformException(
              code: 'gatt-timeout',
              message: 'Discovery timed out',
            ),
          );

          expect(
            () => connectionManager.discoverServices('device-1'),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'discoverServices',
              ),
            ),
          );
        },
      );

      test(
        'writeCharacteristic translates PlatformException(gatt-disconnected) to GattOperationDisconnectedException',
        () async {
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(code: 'gatt-disconnected', message: 'link lost'),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'writeCharacteristic',
              ),
            ),
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
            () => connectionManager.readCharacteristic('device-1', 42),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'readCharacteristic',
              ),
            ),
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

          when(
            () => mockHostApi.setNotification(any(), any(), any()),
          ).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.setNotification('d', 1, true),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'setNotification',
              ),
            ),
          );

          when(
            () => mockHostApi.readDescriptor(any(), any(), any()),
          ).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readDescriptor('d', 1, 2),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'readDescriptor',
              ),
            ),
          );

          when(
            () => mockHostApi.writeDescriptor(any(), any(), any(), any()),
          ).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.writeDescriptor(
              'd',
              1,
              2,
              Uint8List.fromList([0x01]),
            ),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'writeDescriptor',
              ),
            ),
          );

          when(
            () => mockHostApi.requestMtu(any(), any()),
          ).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.requestMtu('d', 200),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'requestMtu',
              ),
            ),
          );

          when(() => mockHostApi.readRssi(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.readRssi('d'),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'readRssi',
              ),
            ),
          );

          when(() => mockHostApi.discoverServices(any())).thenThrow(disconnect);
          await expectLater(
            () => connectionManager.discoverServices('d'),
            throwsA(
              isA<GattOperationDisconnectedException>().having(
                (e) => e.operation,
                'operation',
                'discoverServices',
              ),
            ),
          );
        },
      );

      test(
        'writeCharacteristic translates PlatformException(gatt-status-failed) to GattOperationStatusFailedException',
        () async {
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(
              code: 'gatt-status-failed',
              message: 'Write failed with status: 1',
              details: 1,
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<GattOperationStatusFailedException>()
                  .having(
                    (e) => e.operation,
                    'operation',
                    'writeCharacteristic',
                  )
                  .having((e) => e.status, 'status', 1),
            ),
          );
        },
      );

      test(
        'readCharacteristic translates PlatformException(gatt-status-failed) to GattOperationStatusFailedException',
        () async {
          when(() => mockHostApi.readCharacteristic(any(), any())).thenThrow(
            PlatformException(
              code: 'gatt-status-failed',
              message: 'Read failed with status: 5',
              details: 5,
            ),
          );

          expect(
            () => connectionManager.readCharacteristic('device-1', 42),
            throwsA(
              isA<GattOperationStatusFailedException>()
                  .having((e) => e.operation, 'operation', 'readCharacteristic')
                  .having((e) => e.status, 'status', 5),
            ),
          );
        },
      );

      test(
        'gatt-status-failed without int details defaults status to -1',
        () async {
          // Pigeon sometimes marshals details via String/JSON paths that
          // could arrive as a non-int. Sentinel -1 is the documented
          // fallback rather than throwing or guessing.
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(
              code: 'gatt-status-failed',
              message: 'Write failed',
              details: null,
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<GattOperationStatusFailedException>().having(
                (e) => e.status,
                'status',
                -1,
              ),
            ),
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
          when(
            () => mockHostApi.setNotification(any(), any(), any()),
          ).thenThrow(timeout);
          await expectLater(
            () => connectionManager.setNotification('d', 42, true),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'setNotification',
              ),
            ),
          );

          // readDescriptor
          when(
            () => mockHostApi.readDescriptor(any(), any(), any()),
          ).thenThrow(timeout);
          await expectLater(
            () => connectionManager.readDescriptor('d', 42, 99),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'readDescriptor',
              ),
            ),
          );

          // writeDescriptor
          when(
            () => mockHostApi.writeDescriptor(any(), any(), any(), any()),
          ).thenThrow(timeout);
          await expectLater(
            () => connectionManager.writeDescriptor(
              'd',
              42,
              99,
              Uint8List.fromList([0x01]),
            ),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'writeDescriptor',
              ),
            ),
          );

          // requestMtu
          when(() => mockHostApi.requestMtu(any(), any())).thenThrow(timeout);
          await expectLater(
            () => connectionManager.requestMtu('d', 200),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'requestMtu',
              ),
            ),
          );

          // readRssi
          when(() => mockHostApi.readRssi(any())).thenThrow(timeout);
          await expectLater(
            () => connectionManager.readRssi('d'),
            throwsA(
              isA<GattOperationTimeoutException>().having(
                (e) => e.operation,
                'operation',
                'readRssi',
              ),
            ),
          );
        },
      );

      test(
        'writeCharacteristic translates PlatformException(bluey-permission-denied) '
        'to PlatformPermissionDeniedException',
        () async {
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(
              code: 'bluey-permission-denied',
              message: 'Missing BLUETOOTH_CONNECT permission',
              details: 'BLUETOOTH_CONNECT',
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<PlatformPermissionDeniedException>()
                  .having(
                    (e) => e.permission,
                    'permission',
                    'BLUETOOTH_CONNECT',
                  )
                  .having(
                    (e) => e.operation,
                    'operation',
                    'writeCharacteristic',
                  ),
            ),
          );
        },
      );

      test(
        'writeCharacteristic translates bluey-permission-denied with null details '
        'to permission "unknown"',
        () async {
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(
              code: 'bluey-permission-denied',
              message: 'Missing permission',
              details: null,
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<PlatformPermissionDeniedException>().having(
                (e) => e.permission,
                'permission',
                'unknown',
              ),
            ),
          );
        },
      );

      test(
        'writeCharacteristic translates bluey-permission-denied with non-String details '
        'to permission "unknown"',
        () async {
          when(
            () => mockHostApi.writeCharacteristic(any(), any(), any(), any()),
          ).thenThrow(
            PlatformException(
              code: 'bluey-permission-denied',
              message: 'Missing permission',
              details: 42, // non-String — defensive fallback
            ),
          );

          expect(
            () => connectionManager.writeCharacteristic(
              'device-1',
              42,
              Uint8List.fromList([0x01]),
              true,
            ),
            throwsA(
              isA<PlatformPermissionDeniedException>().having(
                (e) => e.permission,
                'permission',
                'unknown',
              ),
            ),
          );
        },
      );
    });

    group('unimplemented stubs (I035 Stage A)', () {
      // Bond/PHY/connection-parameter methods are not yet wired through
      // Pigeon. Until they are, the stubs must be honest — throw
      // UnimplementedError rather than silently returning hardcoded
      // success values, so callers cannot mistake a no-op for a working
      // implementation.

      test('getBondState throws UnimplementedError', () {
        expect(
          () => connectionManager.getBondState('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('bondStateStream throws UnimplementedError synchronously', () {
        expect(
          () => connectionManager.bondStateStream('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('bond throws UnimplementedError', () {
        expect(
          () => connectionManager.bond('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('removeBond throws UnimplementedError', () {
        expect(
          () => connectionManager.removeBond('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('getBondedDevices throws UnimplementedError', () {
        expect(
          () => connectionManager.getBondedDevices(),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('getPhy throws UnimplementedError', () {
        expect(
          () => connectionManager.getPhy('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('phyStream throws UnimplementedError synchronously', () {
        expect(
          () => connectionManager.phyStream('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('requestPhy throws UnimplementedError', () {
        expect(
          () => connectionManager.requestPhy(
            'device-1',
            PlatformPhy.le1m,
            PlatformPhy.le1m,
          ),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('getConnectionParameters throws UnimplementedError', () {
        expect(
          () => connectionManager.getConnectionParameters('device-1'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('requestConnectionParameters throws UnimplementedError', () {
        expect(
          () => connectionManager.requestConnectionParameters(
            'device-1',
            const PlatformConnectionParameters(
              intervalMs: 30,
              latency: 0,
              timeoutMs: 5000,
            ),
          ),
          throwsA(isA<UnimplementedError>()),
        );
      });
    });
  });
}

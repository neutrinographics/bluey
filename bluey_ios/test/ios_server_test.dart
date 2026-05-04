import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey_ios/src/ios_server.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late IosServer server;

  setUpAll(() {
    registerFallbackValue(
      LocalServiceDto(
        uuid: '',
        isPrimary: true,
        characteristics: [],
        includedServices: [],
      ),
    );
    registerFallbackValue(
      AdvertiseConfigDto(serviceUuids: [], scanResponseServiceUuids: []),
    );
    registerFallbackValue(GattStatusDto.success);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    server = IosServer(mockHostApi);
  });

  group('IosServer', () {
    group('addService', () {
      test('maps PlatformLocalService to DTO correctly', () async {
        when(() => mockHostApi.addService(any())).thenAnswer(
          (invocation) async =>
              invocation.positionalArguments.first as LocalServiceDto,
        );

        final service = PlatformLocalService(
          uuid: '180D',
          isPrimary: true,
          characteristics: [
            PlatformLocalCharacteristic(
              uuid: '2A37',
              properties: PlatformCharacteristicProperties(
                canRead: true,
                canWrite: false,
                canWriteWithoutResponse: false,
                canNotify: true,
                canIndicate: false,
              ),
              permissions: [
                PlatformGattPermission.read,
                PlatformGattPermission.write,
              ],
              descriptors: [
                PlatformLocalDescriptor(
                  uuid: '2902',
                  permissions: [PlatformGattPermission.read],
                  value: Uint8List.fromList([0x00, 0x00]),
                ),
              ],
            ),
          ],
          includedServices: [],
        );

        await server.addService(service);

        final captured =
            verify(() => mockHostApi.addService(captureAny())).captured.single
                as LocalServiceDto;

        expect(captured.uuid, equals('180D'));
        expect(captured.isPrimary, isTrue);
        expect(captured.characteristics, hasLength(1));

        final char = captured.characteristics[0];
        expect(char.uuid, equals('2A37'));
        expect(char.properties.canRead, isTrue);
        expect(char.properties.canWrite, isFalse);
        expect(char.properties.canWriteWithoutResponse, isFalse);
        expect(char.properties.canNotify, isTrue);
        expect(char.properties.canIndicate, isFalse);
        expect(
          char.permissions,
          equals([GattPermissionDto.read, GattPermissionDto.write]),
        );

        expect(char.descriptors, hasLength(1));
        expect(char.descriptors[0].uuid, equals('2902'));
        expect(
          char.descriptors[0].permissions,
          equals([GattPermissionDto.read]),
        );
        expect(char.descriptors[0].value, equals([0x00, 0x00]));

        expect(captured.includedServices, isEmpty);
      });
    });

    group('removeService', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.removeService(any())).thenAnswer((_) async {});

        await server.removeService('180D');

        verify(() => mockHostApi.removeService('180D')).called(1);
      });
    });

    group('startAdvertising', () {
      test('maps config to DTO without mode (iOS has no mode)', () async {
        when(
          () => mockHostApi.startAdvertising(any()),
        ).thenAnswer((_) async {});

        final config = PlatformAdvertiseConfig(
          name: 'TestDevice',
          serviceUuids: ['180D', '180F'],
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: Uint8List.fromList([0x02, 0x15]),
          timeoutMs: 10000,
        );

        await server.startAdvertising(config);

        final captured =
            verify(
                  () => mockHostApi.startAdvertising(captureAny()),
                ).captured.single
                as AdvertiseConfigDto;

        expect(captured.name, equals('TestDevice'));
        expect(captured.serviceUuids, equals(['180D', '180F']));
        expect(captured.manufacturerDataCompanyId, equals(0x004C));
        expect(captured.manufacturerData, equals([0x02, 0x15]));
        expect(captured.timeoutMs, equals(10000));
      });

      test('forwards scanResponseServiceUuids to the Pigeon DTO', () async {
        when(
          () => mockHostApi.startAdvertising(any()),
        ).thenAnswer((_) async {});

        final config = PlatformAdvertiseConfig(
          serviceUuids: const ['svc-1'],
          scanResponseServiceUuids: const ['scan-1'],
        );

        await server.startAdvertising(config);

        final captured =
            verify(
                  () => mockHostApi.startAdvertising(captureAny()),
                ).captured.single
                as AdvertiseConfigDto;

        expect(captured.serviceUuids, equals(['svc-1']));
        expect(captured.scanResponseServiceUuids, equals(['scan-1']));
      });
    });

    group('stopAdvertising', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.stopAdvertising()).thenAnswer((_) async {});

        await server.stopAdvertising();

        verify(() => mockHostApi.stopAdvertising()).called(1);
      });
    });

    group('notifyCharacteristic', () {
      test('calls hostApi', () async {
        when(
          () => mockHostApi.notifyCharacteristic(any(), any()),
        ).thenAnswer((_) async {});

        final value = Uint8List.fromList([0x01, 0x02]);
        await server.notifyCharacteristic(42, value);

        verify(() => mockHostApi.notifyCharacteristic(42, value)).called(1);
      });
    });

    group('notifyCharacteristicTo', () {
      test('calls hostApi', () async {
        when(
          () => mockHostApi.notifyCharacteristicTo(any(), any(), any()),
        ).thenAnswer((_) async {});

        final value = Uint8List.fromList([0x01, 0x02]);
        await server.notifyCharacteristicTo('central-1', 42, value);

        verify(
          () => mockHostApi.notifyCharacteristicTo('central-1', 42, value),
        ).called(1);
      });
    });

    group('indicateCharacteristic', () {
      test(
        'calls notifyCharacteristic on hostApi (same underlying call)',
        () async {
          when(
            () => mockHostApi.notifyCharacteristic(any(), any()),
          ).thenAnswer((_) async {});

          final value = Uint8List.fromList([0x03, 0x04]);
          await server.indicateCharacteristic(42, value);

          verify(() => mockHostApi.notifyCharacteristic(42, value)).called(1);
        },
      );
    });

    group('indicateCharacteristicTo', () {
      test(
        'calls notifyCharacteristicTo on hostApi (same underlying call)',
        () async {
          when(
            () => mockHostApi.notifyCharacteristicTo(any(), any(), any()),
          ).thenAnswer((_) async {});

          final value = Uint8List.fromList([0x03, 0x04]);
          await server.indicateCharacteristicTo('central-1', 42, value);

          verify(
            () => mockHostApi.notifyCharacteristicTo('central-1', 42, value),
          ).called(1);
        },
      );
    });

    group('respondToReadRequest', () {
      test('calls hostApi with correct DTO mapping', () async {
        when(
          () => mockHostApi.respondToReadRequest(any(), any(), any()),
        ).thenAnswer((_) async {});

        final value = Uint8List.fromList([0x42]);
        await server.respondToReadRequest(1, PlatformGattStatus.success, value);

        final captured =
            verify(
              () => mockHostApi.respondToReadRequest(
                captureAny(),
                captureAny(),
                captureAny(),
              ),
            ).captured;

        expect(captured[0], equals(1));
        expect(captured[1], equals(GattStatusDto.success));
        expect(captured[2], equals(value));
      });

      test('maps all gatt status values correctly', () async {
        when(
          () => mockHostApi.respondToReadRequest(any(), any(), any()),
        ).thenAnswer((_) async {});

        for (final (platformStatus, expectedDto) in [
          (PlatformGattStatus.success, GattStatusDto.success),
          (PlatformGattStatus.readNotPermitted, GattStatusDto.readNotPermitted),
          (
            PlatformGattStatus.writeNotPermitted,
            GattStatusDto.writeNotPermitted,
          ),
          (PlatformGattStatus.invalidOffset, GattStatusDto.invalidOffset),
          (
            PlatformGattStatus.invalidAttributeLength,
            GattStatusDto.invalidAttributeLength,
          ),
          (
            PlatformGattStatus.insufficientAuthentication,
            GattStatusDto.insufficientAuthentication,
          ),
          (
            PlatformGattStatus.insufficientEncryption,
            GattStatusDto.insufficientEncryption,
          ),
          (
            PlatformGattStatus.requestNotSupported,
            GattStatusDto.requestNotSupported,
          ),
        ]) {
          await server.respondToReadRequest(1, platformStatus, null);

          final captured =
              verify(
                () => mockHostApi.respondToReadRequest(
                  captureAny(),
                  captureAny(),
                  captureAny(),
                ),
              ).captured;

          expect(captured[1], equals(expectedDto));
        }
      });
    });

    group('respondToWriteRequest', () {
      test('calls hostApi with correct DTO mapping', () async {
        when(
          () => mockHostApi.respondToWriteRequest(any(), any()),
        ).thenAnswer((_) async {});

        await server.respondToWriteRequest(2, PlatformGattStatus.success);

        verify(
          () => mockHostApi.respondToWriteRequest(2, GattStatusDto.success),
        ).called(1);
      });
    });

    group('closeServer', () {
      test('delegates to hostApi', () async {
        when(() => mockHostApi.closeServer()).thenAnswer((_) async {});

        await server.closeServer();

        verify(() => mockHostApi.closeServer()).called(1);
      });
    });

    group('onCentralConnected', () {
      test('emits to connections stream', () async {
        final stream = server.centralConnections;
        final future = stream.first;

        server.onCentralConnected(CentralDto(id: 'central-1', mtu: 512));

        final central = await future;
        expect(central.id, equals('central-1'));
        expect(central.mtu, equals(512));
      });
    });

    group('onCentralDisconnected', () {
      test('emits to disconnections stream', () async {
        final stream = server.centralDisconnections;
        final future = stream.first;

        server.onCentralDisconnected('central-1');

        final centralId = await future;
        expect(centralId, equals('central-1'));
      });
    });

    group('onReadRequest', () {
      test('emits with expanded UUID', () async {
        final stream = server.readRequests;
        final future = stream.first;

        server.onReadRequest(
          ReadRequestDto(
            requestId: 1,
            centralId: 'central-1',
            characteristicUuid: '2A37',
            offset: 0,
            characteristicHandle: 42,
          ),
        );

        final request = await future;
        expect(request.requestId, equals(1));
        expect(request.centralId, equals('central-1'));
        expect(
          request.characteristicUuid,
          equals('00002a37-0000-1000-8000-00805f9b34fb'),
        );
        expect(request.offset, equals(0));
      });
    });

    group('onWriteRequest', () {
      test('emits with expanded UUID', () async {
        final stream = server.writeRequests;
        final future = stream.first;

        final data = Uint8List.fromList([0x01, 0x02]);
        server.onWriteRequest(
          WriteRequestDto(
            requestId: 2,
            centralId: 'central-1',
            characteristicUuid: '2A37',
            value: data,
            offset: 0,
            responseNeeded: true,
            characteristicHandle: 42,
          ),
        );

        final request = await future;
        expect(request.requestId, equals(2));
        expect(request.centralId, equals('central-1'));
        expect(
          request.characteristicUuid,
          equals('00002a37-0000-1000-8000-00805f9b34fb'),
        );
        expect(request.value, equals(data));
        expect(request.offset, equals(0));
        expect(request.responseNeeded, isTrue);
      });
    });
  });
}

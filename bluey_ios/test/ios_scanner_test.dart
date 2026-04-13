import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey_ios/src/ios_scanner.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_ios/src/uuid_utils.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late IosScanner scanner;

  setUpAll(() {
    registerFallbackValue(ScanConfigDto(serviceUuids: []));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    scanner = IosScanner(mockHostApi);
  });

  group('IosScanner', () {
    group('scan', () {
      test('calls hostApi.startScan with correct DTO mapping', () {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(
          serviceUuids: ['180D', '180F'],
          timeoutMs: 5000,
        );

        scanner.scan(config);

        final captured =
            verify(() => mockHostApi.startScan(captureAny())).captured.single
                as ScanConfigDto;

        expect(captured.serviceUuids, equals(['180D', '180F']));
        expect(captured.timeoutMs, equals(5000));
      });

      test('returns the scan stream', () {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(
          serviceUuids: [],
          timeoutMs: null,
        );

        final stream = scanner.scan(config);

        expect(stream, isA<Stream<PlatformDevice>>());
      });
    });

    group('onDeviceDiscovered', () {
      test('emits device with expanded UUIDs', () async {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(
          serviceUuids: [],
          timeoutMs: null,
        );

        final stream = scanner.scan(config);
        final future = stream.first;

        final deviceDto = DeviceDto(
          id: 'ABC12345-1234-5678-9ABC-DEF012345678',
          name: 'Heart Monitor',
          rssi: -55,
          serviceUuids: ['180D'],
        );

        scanner.onDeviceDiscovered(deviceDto);

        final device = await future;

        expect(device.id, equals('ABC12345-1234-5678-9ABC-DEF012345678'));
        expect(device.name, equals('Heart Monitor'));
        expect(device.rssi, equals(-55));
        // Short UUID "180D" must be expanded to full 128-bit format
        expect(
          device.serviceUuids,
          equals(['0000180d-0000-1000-8000-00805f9b34fb']),
        );
        expect(device.manufacturerDataCompanyId, isNull);
        expect(device.manufacturerData, isNull);
      });

      test('maps manufacturer data correctly', () async {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(
          serviceUuids: [],
          timeoutMs: null,
        );

        final stream = scanner.scan(config);
        final future = stream.first;

        final deviceDto = DeviceDto(
          id: 'ABC12345-1234-5678-9ABC-DEF012345678',
          name: null,
          rssi: -72,
          serviceUuids: [],
          manufacturerDataCompanyId: 0x004C,
          manufacturerData: [0x02, 0x15, 0x01],
        );

        scanner.onDeviceDiscovered(deviceDto);

        final device = await future;

        expect(device.manufacturerDataCompanyId, equals(0x004C));
        expect(device.manufacturerData, equals([0x02, 0x15, 0x01]));
      });
    });

    group('stopScan', () {
      test('calls hostApi.stopScan', () async {
        when(() => mockHostApi.stopScan()).thenAnswer((_) async {});

        await scanner.stopScan();

        verify(() => mockHostApi.stopScan()).called(1);
      });
    });

    group('onScanComplete', () {
      test('does not throw', () {
        expect(() => scanner.onScanComplete(), returnsNormally);
      });
    });
  });

  group('expandUuid', () {
    test('expands 16-bit short UUID to full 128-bit', () {
      expect(
        expandUuid('180D'),
        equals('0000180d-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('expands 32-bit short UUID to full 128-bit', () {
      expect(
        expandUuid('12345678'),
        equals('12345678-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('passes through full 128-bit UUID unchanged', () {
      expect(
        expandUuid('01234567-89ab-cdef-0123-456789abcdef'),
        equals('01234567-89ab-cdef-0123-456789abcdef'),
      );
    });

    test('normalizes case to lowercase', () {
      expect(
        expandUuid('0000180D-0000-1000-8000-00805F9B34FB'),
        equals('0000180d-0000-1000-8000-00805f9b34fb'),
      );
    });

    test('handles full UUID without hyphens', () {
      expect(
        expandUuid('0123456789abcdef0123456789abcdef'),
        equals('01234567-89ab-cdef-0123-456789abcdef'),
      );
    });
  });
}

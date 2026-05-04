import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey_android/src/android_scanner.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late AndroidScanner scanner;

  setUpAll(() {
    registerFallbackValue(ScanConfigDto(serviceUuids: []));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    scanner = AndroidScanner(mockHostApi);
  });

  group('AndroidScanner', () {
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

        final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);

        final stream = scanner.scan(config);

        expect(stream, isA<Stream<PlatformDevice>>());
      });
    });

    group('onDeviceDiscovered', () {
      test('emits device to scan stream with correct mapping', () async {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);

        final stream = scanner.scan(config);
        final future = stream.first;

        final deviceDto = DeviceDto(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'Test Device',
          rssi: -65,
          serviceUuids: ['180D'],
        );

        scanner.onDeviceDiscovered(deviceDto);

        final device = await future;

        expect(device.id, equals('AA:BB:CC:DD:EE:FF'));
        expect(device.name, equals('Test Device'));
        expect(device.rssi, equals(-65));
        expect(device.serviceUuids, equals(['180D']));
        expect(device.manufacturerDataCompanyId, isNull);
        expect(device.manufacturerData, isNull);
      });

      test('maps manufacturer data correctly', () async {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);

        final stream = scanner.scan(config);
        final future = stream.first;

        final deviceDto = DeviceDto(
          id: 'AA:BB:CC:DD:EE:FF',
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
}

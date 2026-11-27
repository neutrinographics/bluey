import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
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

      test('maps the scan mode into the DTO', () {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(
          serviceUuids: [],
          timeoutMs: null,
          scanMode: PlatformScanMode.lowPower,
        );

        scanner.scan(config);

        final captured =
            verify(() => mockHostApi.startScan(captureAny())).captured.single
                as ScanConfigDto;

        expect(captured.mode, equals(ScanModeDto.lowPower));
      });

      test('a null scan mode crosses as null — the native default '
          '(lowLatency) applies', () {
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});

        final config = PlatformScanConfig(serviceUuids: [], timeoutMs: null);

        scanner.scan(config);

        final captured =
            verify(() => mockHostApi.startScan(captureAny())).captured.single
                as ScanConfigDto;

        expect(captured.mode, isNull);
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

    group('a refused scan', () {
      PlatformScanConfig config() =>
          PlatformScanConfig(serviceUuids: const [], timeoutMs: null);

      test('M2 (I013): a rejected startScan surfaces on the scan stream, not '
          'as an unhandled async error', () async {
        // arrange
        when(() => mockHostApi.startScan(any())).thenAnswer(
          (_) async =>
              throw PlatformException(code: 'permission-denied', message: 'x'),
        );
        final unhandled = <Object>[];
        final streamErrors = <Object>[];

        // act
        runZonedGuarded(() {
          scanner.scan(config()).listen((_) {}, onError: streamErrors.add);
        }, (e, _) => unhandled.add(e));
        await pumpEventQueue();

        // assert
        expect(unhandled, isEmpty);
        expect(streamErrors, hasLength(1));
      });

      test('onScanFailed(2) puts registrationFailed with its code on the '
          'stream', () async {
        // arrange
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});
        final errors = <Object>[];
        scanner.scan(config()).listen((_) {}, onError: errors.add);

        // act
        scanner.onScanFailed(2);
        await pumpEventQueue();

        // assert
        final error = errors.single as PlatformScanFailedException;
        expect(error.reason, PlatformScanFailureReason.registrationFailed);
        expect(error.code, 2);
      });

      test('Android codes 1 to 6 map in order to their reasons', () async {
        // arrange
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});
        final errors = <Object>[];
        scanner.scan(config()).listen((_) {}, onError: errors.add);

        // act
        for (var code = 1; code <= 6; code++) {
          scanner.onScanFailed(code);
        }
        await pumpEventQueue();

        // assert
        expect(
          errors.cast<PlatformScanFailedException>().map((e) => e.reason),
          [
            PlatformScanFailureReason.alreadyStarted,
            PlatformScanFailureReason.registrationFailed,
            PlatformScanFailureReason.internalError,
            PlatformScanFailureReason.unsupported,
            PlatformScanFailureReason.outOfHardwareResources,
            PlatformScanFailureReason.startedTooOften,
          ],
        );
      });

      test('onScanFailed(99) is unknown and keeps the code', () async {
        // arrange
        when(() => mockHostApi.startScan(any())).thenAnswer((_) async {});
        final errors = <Object>[];
        scanner.scan(config()).listen((_) {}, onError: errors.add);

        // act
        scanner.onScanFailed(99);
        await pumpEventQueue();

        // assert
        final error = errors.single as PlatformScanFailedException;
        expect(error.reason, PlatformScanFailureReason.unknown);
        expect(error.code, 99);
      });

      test('a rejection that a later scan superseded is dropped', () async {
        // arrange
        final first = Completer<void>();
        var calls = 0;
        when(() => mockHostApi.startScan(any())).thenAnswer((_) {
          calls++;
          return calls == 1 ? first.future : Future<void>.value();
        });
        final errors = <Object>[];
        scanner.scan(config()).listen((_) {}, onError: errors.add);
        scanner.scan(config());

        // act
        first.completeError(PlatformException(code: 'late'));
        await pumpEventQueue();

        // assert
        expect(errors, isEmpty);
      });

      test('a rejection that a later stopScan superseded is dropped', () async {
        // arrange
        final start = Completer<void>();
        when(
          () => mockHostApi.startScan(any()),
        ).thenAnswer((_) => start.future);
        when(() => mockHostApi.stopScan()).thenAnswer((_) async {});
        final errors = <Object>[];
        scanner.scan(config()).listen((_) {}, onError: errors.add);
        await scanner.stopScan();

        // act
        start.completeError(PlatformException(code: 'late'));
        await pumpEventQueue();

        // assert
        expect(errors, isEmpty);
      });
    });
  });
}

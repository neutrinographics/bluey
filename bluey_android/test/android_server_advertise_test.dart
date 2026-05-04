import 'dart:typed_data';

import 'package:bluey_android/src/android_server.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBlueyHostApi mockHostApi;
  late AndroidServer server;

  setUpAll(() {
    registerFallbackValue(
      AdvertiseConfigDto(serviceUuids: [], scanResponseServiceUuids: []),
    );
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockHostApi = MockBlueyHostApi();
    server = AndroidServer(mockHostApi);
  });

  group('AndroidServer.startAdvertising — DTO mapping', () {
    test('forwards scanResponseServiceUuids to the Pigeon DTO', () async {
      when(
        () => mockHostApi.startAdvertising(any()),
      ).thenAnswer((_) async {});

      await server.startAdvertising(
        const PlatformAdvertiseConfig(
          serviceUuids: ['svc-1'],
          scanResponseServiceUuids: ['scan-1'],
        ),
      );

      final captured = verify(
        () => mockHostApi.startAdvertising(captureAny()),
      ).captured.single as AdvertiseConfigDto;

      expect(captured.serviceUuids, equals(['svc-1']));
      expect(captured.scanResponseServiceUuids, equals(['scan-1']));
    });
  });

  group('AndroidServer.startAdvertising — error translation', () {
    test(
      'PlatformException(bluey-advertise-data-too-large) -> PlatformAdvertiseDataTooLargeException',
      () async {
        when(() => mockHostApi.startAdvertising(any())).thenThrow(
          PlatformException(
            code: 'bluey-advertise-data-too-large',
            message: 'Advertise data too large',
          ),
        );

        await expectLater(
          server.startAdvertising(
            const PlatformAdvertiseConfig(serviceUuids: ['svc-1']),
          ),
          throwsA(
            isA<PlatformAdvertiseDataTooLargeException>().having(
              (e) => e.message,
              'message',
              'Advertise data too large',
            ),
          ),
        );
      },
    );

    test('other PlatformException codes propagate unchanged', () async {
      when(() => mockHostApi.startAdvertising(any())).thenThrow(
        PlatformException(code: 'bluey-unknown', message: 'something else'),
      );

      await expectLater(
        server.startAdvertising(
          const PlatformAdvertiseConfig(serviceUuids: ['svc-1']),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'bluey-unknown',
          ),
        ),
      );
    });
  });
}

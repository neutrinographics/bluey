/// Known defects from the audit of 2026-11-17
/// (docs/reviews/2026-11-17-correctness-and-test-rig-audit.md).
///
/// Each test asserts what an app would reasonably expect and fails today.
/// The slice that fixes a defect moves its test into the suite of the code
/// it fixes and takes it out of this file.
@Tags(['known-defect'])
library;

import 'dart:async';

import 'package:bluey_android/src/android_connection_manager.dart';
import 'package:bluey_android/src/android_scanner.dart';
import 'package:bluey_android/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(ConnectConfigDto());
    registerFallbackValue(ScanConfigDto(serviceUuids: []));
  });

  test(
    'M3 (I369): a second connect() to a connected device does not orphan the '
    'first connection\'s state stream',
    () async {
      // arrange
      final hostApi = MockBlueyHostApi();
      final manager = AndroidConnectionManager(hostApi);
      when(() => hostApi.connect(any(), any())).thenAnswer((_) async => 'dev');
      const config = PlatformConnectConfig(timeoutMs: null, mtu: null);

      await manager.connect('dev', config);
      final states = <PlatformConnectionState>[];
      manager.connectionStateStream('dev').listen(states.add);

      // act
      // Native connect is idempotent for an already-connected device.
      await manager.connect('dev', config);
      manager.onConnectionStateChanged(
        ConnectionStateEventDto(
          deviceId: 'dev',
          state: ConnectionStateDto.disconnected,
        ),
      );
      await pumpEventQueue();

      // assert
      expect(
        states,
        contains(PlatformConnectionState.disconnected),
        reason: 'the first Connection never learns the link dropped',
      );
    },
  );

  test('M2 (I013): a rejected startScan surfaces on the scan stream, not as an '
      'unhandled async error', () async {
    // arrange
    final hostApi = MockBlueyHostApi();
    final scanner = AndroidScanner(hostApi);
    when(() => hostApi.startScan(any())).thenAnswer(
      (_) async =>
          throw PlatformException(code: 'permission-denied', message: 'x'),
    );
    final unhandled = <Object>[];
    final streamErrors = <Object>[];

    // act
    runZonedGuarded(() {
      scanner
          .scan(PlatformScanConfig(serviceUuids: const [], timeoutMs: null))
          .listen((_) {}, onError: streamErrors.add);
    }, (e, _) => unhandled.add(e));
    await pumpEventQueue();

    // assert
    expect(unhandled, isEmpty, reason: 'scan-start failure escapes the API');
    expect(streamErrors, isNotEmpty, reason: 'scan stream stays silent');
  });
}

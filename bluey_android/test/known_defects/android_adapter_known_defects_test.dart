/// Known defects from the audit of 2026-11-17
/// (docs/reviews/2026-11-17-correctness-and-test-rig-audit.md).
///
/// Each test asserts what an app would reasonably expect and fails today.
/// The slice that fixes a defect moves its test into the suite of the code
/// it fixes and takes it out of this file.
@Tags(['known-defect'])
library;

import 'dart:async';

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
    registerFallbackValue(ScanConfigDto(serviceUuids: []));
  });

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

import 'package:bluey_ios/src/ios_server.dart';
import 'package:bluey_ios/src/messages.g.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(GattStatusDto.success);
  });

  group('IosServer.respondToReadRequest — error translation', () {
    test(
      'PlatformException(bluey-not-found) -> PlatformRespondToRequestNotFoundException',
      () async {
        final mockHostApi = MockBlueyHostApi();
        when(
          () => mockHostApi.respondToReadRequest(any(), any(), any()),
        ).thenThrow(
          PlatformException(
            code: 'bluey-not-found',
            message: 'Pending request 42 not found',
          ),
        );
        final server = IosServer(mockHostApi);

        await expectLater(
          server.respondToReadRequest(42, PlatformGattStatus.success, null),
          throwsA(
            isA<PlatformRespondToRequestNotFoundException>().having(
              (e) => e.message,
              'message',
              'Pending request 42 not found',
            ),
          ),
        );
      },
    );

    test(
      'other PlatformException codes propagate unchanged (regression guard)',
      () async {
        final mockHostApi = MockBlueyHostApi();
        when(
          () => mockHostApi.respondToReadRequest(any(), any(), any()),
        ).thenThrow(
          PlatformException(
            code: 'bluey-unknown',
            message: 'something else',
          ),
        );
        final server = IosServer(mockHostApi);

        await expectLater(
          server.respondToReadRequest(99, PlatformGattStatus.success, null),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'bluey-unknown',
            ),
          ),
        );
      },
    );

    test(
      'gatt-status-failed code propagates unchanged (does NOT spuriously translate)',
      () async {
        // Sanity check: pre-Option-A, the Swift side could emit
        // gatt-status-failed for the not-found path. After this change, it
        // emits bluey-not-found instead. If something *else* emits
        // gatt-status-failed for a legitimate reason, the wrapper should
        // not capture it.
        final mockHostApi = MockBlueyHostApi();
        when(
          () => mockHostApi.respondToReadRequest(any(), any(), any()),
        ).thenThrow(
          PlatformException(
            code: 'gatt-status-failed',
            message: 'genuine ATT failure',
            details: 0x0A,
          ),
        );
        final server = IosServer(mockHostApi);

        await expectLater(
          server.respondToReadRequest(7, PlatformGattStatus.success, null),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'gatt-status-failed',
            ),
          ),
        );
      },
    );
  });
}

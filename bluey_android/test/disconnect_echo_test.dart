import 'package:bluey_android/src/disconnect_echo.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DisconnectEcho echo;

  setUp(() {
    echo = DisconnectEcho();
  });

  group('the echo of a disconnect request', () {
    test('the disconnecting report after a request is the echo', () {
      // arrange
      echo.expectFor('dev');

      // act
      final isEcho = echo.isEcho('dev', PlatformConnectionState.disconnecting);

      // assert
      expect(isEcho, isTrue);
    });

    test('an echo is recognised once', () {
      // arrange
      echo.expectFor('dev');
      echo.isEcho('dev', PlatformConnectionState.disconnecting);

      // act
      final isEcho = echo.isEcho('dev', PlatformConnectionState.disconnecting);

      // assert
      expect(isEcho, isFalse);
    });

    test('a disconnecting report with no request is not an echo', () {
      // act
      final isEcho = echo.isEcho('dev', PlatformConnectionState.disconnecting);

      // assert
      expect(isEcho, isFalse);
    });

    test('a disconnected report means no echo is coming', () {
      // arrange
      echo.expectFor('dev');

      // act
      final disconnectedIsEcho = echo.isEcho(
        'dev',
        PlatformConnectionState.disconnected,
      );
      final laterIsEcho = echo.isEcho(
        'dev',
        PlatformConnectionState.disconnecting,
      );

      // assert
      expect(disconnectedIsEcho, isFalse);
      expect(laterIsEcho, isFalse);
    });

    test('two requests before the echo expect one echo', () {
      // arrange
      echo.expectFor('dev');
      echo.expectFor('dev');

      // act
      final first = echo.isEcho('dev', PlatformConnectionState.disconnecting);
      final second = echo.isEcho('dev', PlatformConnectionState.disconnecting);

      // assert
      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('a request for one device expects no echo from another', () {
      // arrange
      echo.expectFor('a');

      // act
      final fromB = echo.isEcho('b', PlatformConnectionState.disconnecting);
      final fromA = echo.isEcho('a', PlatformConnectionState.disconnecting);

      // assert
      expect(fromB, isFalse);
      expect(fromA, isTrue);
    });

    test('connecting and connected reports are never the echo and leave it '
        'expected', () {
      // arrange
      echo.expectFor('dev');

      // act
      final connecting = echo.isEcho('dev', PlatformConnectionState.connecting);
      final connected = echo.isEcho('dev', PlatformConnectionState.connected);
      final disconnecting = echo.isEcho(
        'dev',
        PlatformConnectionState.disconnecting,
      );

      // assert
      expect(connecting, isFalse);
      expect(connected, isFalse);
      expect(disconnecting, isTrue);
    });
  });
}

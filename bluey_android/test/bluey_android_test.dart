import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_android/bluey_android.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlueyAndroid', () {
    test('registers as platform instance', () {
      BlueyAndroid.registerWith();
      expect(BlueyPlatform.instance, isA<BlueyAndroid>());
    });

    test('has Android capabilities', () {
      final bluey = BlueyAndroid();
      expect(bluey.capabilities, equals(Capabilities.android));
    });

    test('resetServerSessions forwards to the host API channel', () async {
      const channelName =
          'dev.flutter.pigeon.bluey_android.BlueyHostApi.resetServerSessions';
      const codec = StandardMessageCodec();
      var invoked = false;

      TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .setMockMessageHandler(channelName, (message) async {
            invoked = true;
            // Pigeon void reply: a single-element list wrapping the result.
            return codec.encodeMessage(<Object?>[null]);
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .setMockMessageHandler(channelName, null),
      );

      final bluey = BlueyAndroid();
      await bluey.resetServerSessions();

      expect(
        invoked,
        isTrue,
        reason:
            'BlueyAndroid.resetServerSessions() must delegate to the native '
            'host API instead of no-opping via the BlueyPlatform base method.',
      );
    });
  });
}

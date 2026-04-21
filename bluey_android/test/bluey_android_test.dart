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
  });
}

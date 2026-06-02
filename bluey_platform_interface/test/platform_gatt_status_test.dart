import 'package:bluey_platform_interface/src/platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PlatformGattStatus exposes a reserved lifecycleEviction case', () {
    expect(PlatformGattStatus.values, contains(PlatformGattStatus.lifecycleEviction));
  });

  test('lifecycleEviction is the last case (additive, stable ordinals)', () {
    expect(PlatformGattStatus.values.last, PlatformGattStatus.lifecycleEviction);
  });
}

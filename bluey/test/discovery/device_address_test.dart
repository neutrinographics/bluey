import 'package:bluey/src/discovery/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceAddress', () {
    test('preserves an Android MAC verbatim (no transformation)', () {
      const a = DeviceAddress('46:F9:31:94:D7:F6');
      expect(a.value, '46:F9:31:94:D7:F6');
      expect(a.toString(), '46:F9:31:94:D7:F6');
    });

    test('preserves an iOS UUID string verbatim', () {
      const a = DeviceAddress('dcee33dc-985a-48f5-87a9-670804c2c0de');
      expect(a.value, 'dcee33dc-985a-48f5-87a9-670804c2c0de');
    });

    test('equality is by value', () {
      const a = DeviceAddress('46:F9:31:94:D7:F6');
      const b = DeviceAddress('46:F9:31:94:D7:F6');
      const c = DeviceAddress('AA:BB:CC:DD:EE:FF');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toShortString truncates long values, leaves short ones', () {
      expect(const DeviceAddress('46:F9:31:94:D7:F6').toShortString(), '46:F9:31');
      expect(const DeviceAddress('short').toShortString(), 'short');
    });
  });
}

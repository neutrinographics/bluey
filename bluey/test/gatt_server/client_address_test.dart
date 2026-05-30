import 'package:bluey/src/gatt_server/client_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientAddress', () {
    test('preserves an Android MAC verbatim', () {
      const a = ClientAddress('46:F9:31:94:D7:F6');
      expect(a.value, '46:F9:31:94:D7:F6');
      expect(a.toString(), '46:F9:31:94:D7:F6');
    });

    test('equality is by value', () {
      const a = ClientAddress('46:F9:31:94:D7:F6');
      const b = ClientAddress('46:F9:31:94:D7:F6');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(const ClientAddress('AA:BB:CC:DD:EE:FF'))));
    });

    test('toShortString truncates long values', () {
      expect(const ClientAddress('46:F9:31:94:D7:F6').toShortString(), '46:F9:31');
      expect(const ClientAddress('short').toShortString(), 'short');
    });
  });
}

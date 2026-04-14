import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattTimeouts', () {
    test('has sane defaults', () {
      const timeouts = GattTimeouts();

      expect(timeouts.discoverServices, const Duration(seconds: 15));
      expect(timeouts.readCharacteristic, const Duration(seconds: 10));
      expect(timeouts.writeCharacteristic, const Duration(seconds: 10));
      expect(timeouts.readDescriptor, const Duration(seconds: 10));
      expect(timeouts.writeDescriptor, const Duration(seconds: 10));
      expect(timeouts.requestMtu, const Duration(seconds: 10));
      expect(timeouts.readRssi, const Duration(seconds: 5));
    });

    test('allows custom values', () {
      const timeouts = GattTimeouts(
        discoverServices: Duration(seconds: 30),
        readRssi: Duration(seconds: 2),
      );

      expect(timeouts.discoverServices, const Duration(seconds: 30));
      expect(timeouts.readRssi, const Duration(seconds: 2));
      expect(timeouts.readCharacteristic, const Duration(seconds: 10));
    });

    test('equality by value', () {
      const t1 = GattTimeouts();
      const t2 = GattTimeouts();
      const t3 = GattTimeouts(discoverServices: Duration(seconds: 30));

      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
    });
  });
}

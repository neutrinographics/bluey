import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mtu', () {
    test('accepts the range the specification allows', () {
      expect((Mtu(23).value, Mtu(517).value), (23, 517));
    });

    test('refuses a value outside it', () {
      expect(() => Mtu(22), throwsArgumentError);
      expect(() => Mtu(518), throwsArgumentError);
    });

    test(
      'names the specification maximum when it refuses a value above it',
      () {
        expect(
          () => Mtu(518),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'MTU must be <= 517 (BLE spec maximum): 518',
            ),
          ),
        );
      },
    );

    test('fromPlatform keeps what the platform reported', () {
      expect(Mtu.fromPlatform(600).value, 600);
      expect(Mtu.fromPlatform(20).value, 20);
    });

    test('Mtu.minimum.value is 23', () {
      expect(Mtu.minimum.value, 23);
    });

    test('two Mtu instances with the same value are equal', () {
      expect(Mtu(100), equals(Mtu(100)));
    });

    test('two Mtu instances with the same value share a hash code', () {
      expect(Mtu(100).hashCode, equals(Mtu(100).hashCode));
    });

    test('two Mtu instances with different values are not equal', () {
      expect(Mtu(100), isNot(equals(Mtu(101))));
    });

    test('toString includes the wrapped value', () {
      expect(Mtu(100).toString(), contains('100'));
    });
  });
}

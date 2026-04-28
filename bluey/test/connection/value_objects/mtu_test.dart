import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mtu', () {
    const androidCaps = Capabilities.android;
    const iosCaps = Capabilities.iOS;

    test('constructs at BLE minimum (23) with Android capabilities', () {
      final mtu = Mtu(23, capabilities: androidCaps);
      expect(mtu.value, 23);
    });

    test('constructs at Android maximum (517) with Android capabilities', () {
      expect(androidCaps.maxMtu, 517);
      final mtu = Mtu(517, capabilities: androidCaps);
      expect(mtu.value, 517);
    });

    test('throws ArgumentError above Android maximum (518)', () {
      expect(
        () => Mtu(518, capabilities: androidCaps),
        throwsArgumentError,
      );
    });

    test('constructs at iOS maximum (185) with iOS capabilities', () {
      expect(iosCaps.maxMtu, 185);
      final mtu = Mtu(185, capabilities: iosCaps);
      expect(mtu.value, 185);
    });

    test('throws ArgumentError above iOS maximum (186)', () {
      expect(
        () => Mtu(186, capabilities: iosCaps),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError below BLE minimum (22)', () {
      expect(
        () => Mtu(22, capabilities: androidCaps),
        throwsArgumentError,
      );
      expect(
        () => Mtu(22, capabilities: iosCaps),
        throwsArgumentError,
      );
    });

    test('Mtu.minimum.value is 23', () {
      expect(Mtu.minimum.value, 23);
    });

    test('Mtu.fromPlatform(517) succeeds without capabilities', () {
      final mtu = Mtu.fromPlatform(517);
      expect(mtu.value, 517);
    });

    test('Mtu.fromPlatform(20) succeeds (no validation)', () {
      final mtu = Mtu.fromPlatform(20);
      expect(mtu.value, 20);
    });

    test('two Mtu instances with the same value are equal', () {
      expect(
        Mtu(100, capabilities: androidCaps),
        equals(Mtu(100, capabilities: androidCaps)),
      );
    });

    test('two Mtu instances with the same value share a hash code', () {
      expect(
        Mtu(100, capabilities: androidCaps).hashCode,
        equals(Mtu(100, capabilities: androidCaps).hashCode),
      );
    });

    test('two Mtu instances with different values are not equal', () {
      expect(
        Mtu(100, capabilities: androidCaps),
        isNot(equals(Mtu(101, capabilities: androidCaps))),
      );
    });

    test('toString includes the wrapped value', () {
      expect(Mtu(100, capabilities: androidCaps).toString(), contains('100'));
    });
  });
}

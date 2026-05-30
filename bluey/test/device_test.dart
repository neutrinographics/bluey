import 'package:bluey/src/discovery/device.dart';
import 'package:bluey/src/discovery/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Device', () {
    test('is identified by its address', () {
      final d = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'));
      expect(d.address, const DeviceAddress('AA:BB:CC:DD:EE:FF'));
    });

    test('entity equality is by address only', () {
      final a = Device(
        address: const DeviceAddress('AA:BB:CC:DD:EE:FF'),
        name: 'x',
      );
      final b = Device(
        address: const DeviceAddress('AA:BB:CC:DD:EE:FF'),
        name: 'y',
      );
      final c = Device(address: const DeviceAddress('11:22:33:44:55:66'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith preserves address, updates name', () {
      final a = Device(
        address: const DeviceAddress('AA:BB:CC:DD:EE:FF'),
        name: 'x',
      );
      expect(a.copyWith(name: 'z').name, 'z');
      expect(a.copyWith(name: 'z').address, a.address);
    });

    test('copyWith can clear name to null', () {
      final a = Device(
        address: const DeviceAddress('AA:BB:CC:DD:EE:FF'),
        name: 'x',
      );
      expect(a.copyWith(name: null).name, isNull);
    });

    test('creates without name', () {
      final d = Device(address: const DeviceAddress('AA:BB:CC:DD:EE:FF'));
      expect(d.name, isNull);
    });
  });
}

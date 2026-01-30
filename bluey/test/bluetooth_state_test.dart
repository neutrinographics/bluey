import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BluetoothState', () {
    test('has all expected values', () {
      expect(BluetoothState.values, hasLength(5));
      expect(BluetoothState.values, contains(BluetoothState.unknown));
      expect(BluetoothState.values, contains(BluetoothState.unsupported));
      expect(BluetoothState.values, contains(BluetoothState.unauthorized));
      expect(BluetoothState.values, contains(BluetoothState.off));
      expect(BluetoothState.values, contains(BluetoothState.on));
    });

    group('isReady', () {
      test('returns false for unknown', () {
        expect(BluetoothState.unknown.isReady, isFalse);
      });

      test('returns false for unsupported', () {
        expect(BluetoothState.unsupported.isReady, isFalse);
      });

      test('returns false for unauthorized', () {
        expect(BluetoothState.unauthorized.isReady, isFalse);
      });

      test('returns false for off', () {
        expect(BluetoothState.off.isReady, isFalse);
      });

      test('returns true for on', () {
        expect(BluetoothState.on.isReady, isTrue);
      });
    });

    group('canBeEnabled', () {
      test('returns false for unknown', () {
        expect(BluetoothState.unknown.canBeEnabled, isFalse);
      });

      test('returns false for unsupported', () {
        expect(BluetoothState.unsupported.canBeEnabled, isFalse);
      });

      test('returns false for unauthorized', () {
        expect(BluetoothState.unauthorized.canBeEnabled, isFalse);
      });

      test('returns true for off', () {
        expect(BluetoothState.off.canBeEnabled, isTrue);
      });

      test('returns false for on (already enabled)', () {
        expect(BluetoothState.on.canBeEnabled, isFalse);
      });
    });
  });
}

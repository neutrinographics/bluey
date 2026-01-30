import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionState', () {
    test('has all expected values', () {
      expect(ConnectionState.values, hasLength(4));
      expect(ConnectionState.values, contains(ConnectionState.disconnected));
      expect(ConnectionState.values, contains(ConnectionState.connecting));
      expect(ConnectionState.values, contains(ConnectionState.connected));
      expect(ConnectionState.values, contains(ConnectionState.disconnecting));
    });

    group('isActive', () {
      test('returns false for disconnected', () {
        expect(ConnectionState.disconnected.isActive, isFalse);
      });

      test('returns true for connecting', () {
        expect(ConnectionState.connecting.isActive, isTrue);
      });

      test('returns true for connected', () {
        expect(ConnectionState.connected.isActive, isTrue);
      });

      test('returns false for disconnecting', () {
        expect(ConnectionState.disconnecting.isActive, isFalse);
      });
    });

    group('isConnected', () {
      test('returns false for disconnected', () {
        expect(ConnectionState.disconnected.isConnected, isFalse);
      });

      test('returns false for connecting', () {
        expect(ConnectionState.connecting.isConnected, isFalse);
      });

      test('returns true for connected', () {
        expect(ConnectionState.connected.isConnected, isTrue);
      });

      test('returns false for disconnecting', () {
        expect(ConnectionState.disconnecting.isConnected, isFalse);
      });
    });
  });
}

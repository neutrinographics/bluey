import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionState', () {
    test('has all expected values (I067 split connected → linked + ready)', () {
      expect(ConnectionState.values, hasLength(5));
      expect(ConnectionState.values, contains(ConnectionState.disconnected));
      expect(ConnectionState.values, contains(ConnectionState.connecting));
      expect(ConnectionState.values, contains(ConnectionState.linked));
      expect(ConnectionState.values, contains(ConnectionState.ready));
      expect(ConnectionState.values, contains(ConnectionState.disconnecting));
    });

    group('isActive', () {
      test('returns false for disconnected', () {
        expect(ConnectionState.disconnected.isActive, isFalse);
      });

      test('returns true for connecting', () {
        expect(ConnectionState.connecting.isActive, isTrue);
      });

      test('returns true for linked', () {
        expect(ConnectionState.linked.isActive, isTrue);
      });

      test('returns true for ready', () {
        expect(ConnectionState.ready.isActive, isTrue);
      });

      test('returns false for disconnecting', () {
        expect(ConnectionState.disconnecting.isActive, isFalse);
      });
    });

    group('isConnected (link is up — linked OR ready)', () {
      test('returns false for disconnected', () {
        expect(ConnectionState.disconnected.isConnected, isFalse);
      });

      test('returns false for connecting', () {
        expect(ConnectionState.connecting.isConnected, isFalse);
      });

      test('returns true for linked', () {
        expect(ConnectionState.linked.isConnected, isTrue);
      });

      test('returns true for ready', () {
        expect(ConnectionState.ready.isConnected, isTrue);
      });

      test('returns false for disconnecting', () {
        expect(ConnectionState.disconnecting.isConnected, isFalse);
      });
    });

    group('isReady (services discovered, GATT ops safe — only ready)', () {
      test('returns false for disconnected', () {
        expect(ConnectionState.disconnected.isReady, isFalse);
      });

      test('returns false for connecting', () {
        expect(ConnectionState.connecting.isReady, isFalse);
      });

      test('returns false for linked', () {
        expect(ConnectionState.linked.isReady, isFalse);
      });

      test('returns true for ready', () {
        expect(ConnectionState.ready.isReady, isTrue);
      });

      test('returns false for disconnecting', () {
        expect(ConnectionState.disconnecting.isReady, isFalse);
      });
    });
  });
}

import 'dart:typed_data';

import 'package:bluey/src/peer/server_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerId', () {
    test('constructor normalizes to lowercase', () {
      final id = ServerId('ABCDEF00-1234-5678-9ABC-DEF012345678');
      expect(id.value, 'abcdef00-1234-5678-9abc-def012345678');
    });

    test('constructor rejects malformed strings', () {
      expect(() => ServerId('not-a-uuid'), throwsArgumentError);
      expect(() => ServerId(''), throwsArgumentError);
    });

    test('generate() produces distinct UUIDs', () {
      final a = ServerId.generate();
      final b = ServerId.generate();
      expect(a, isNot(equals(b)));
    });

    test('equality by value', () {
      final a = ServerId('abcdef00-1234-5678-9abc-def012345678');
      final b = ServerId('ABCDEF00-1234-5678-9ABC-DEF012345678');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toBytes produces 16 bytes and round-trips via fromBytes', () {
      final original = ServerId.generate();
      final bytes = original.toBytes();
      expect(bytes, hasLength(16));
      final roundTrip = ServerId.fromBytes(bytes);
      expect(roundTrip, equals(original));
    });

    test('fromBytes rejects non-16-byte input', () {
      expect(
        () => ServerId.fromBytes(Uint8List.fromList(List.filled(15, 0))),
        throwsArgumentError,
      );
      expect(
        () => ServerId.fromBytes(Uint8List.fromList(List.filled(17, 0))),
        throwsArgumentError,
      );
    });

    test('toString returns the canonical value', () {
      final id = ServerId('abcdef00-1234-5678-9abc-def012345678');
      expect(id.toString(), 'abcdef00-1234-5678-9abc-def012345678');
    });
  });
}

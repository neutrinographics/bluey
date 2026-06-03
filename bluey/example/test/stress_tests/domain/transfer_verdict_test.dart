import 'dart:typed_data';

import 'package:bluey_example/features/stress_tests/domain/transfer_verdict.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pattern(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => i & 0xff));

void main() {
  group('evaluateTransfer', () {
    test('exact match returns ok', () {
      final v = evaluateTransfer(expectedLen: 600, readBack: pattern(600));
      expect(v.ok, isTrue);
      expect(v.expectedLen, equals(600));
      expect(v.gotLen, equals(600));
    });

    test('truncated read-back diverges at the cut, with no gotByte', () {
      // Client expected 514 bytes; only 512 arrived (the I343 symptom).
      final v = evaluateTransfer(expectedLen: 514, readBack: pattern(512));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(512));
      expect(v.expectedByte, equals(512 & 0xff));
      expect(v.gotByte, isNull);
      expect(v.expectedLen, equals(514));
      expect(v.gotLen, equals(512));
    });

    test('a wrong byte mid-stream diverges at that offset', () {
      final corrupted = pattern(100);
      corrupted[42] = 0xFF; // pattern[42] would be 42
      final v = evaluateTransfer(expectedLen: 100, readBack: corrupted);
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(42));
      expect(v.expectedByte, equals(42));
      expect(v.gotByte, equals(0xFF));
    });

    test('empty read-back against a non-empty expectation diverges at 0', () {
      final v = evaluateTransfer(expectedLen: 8, readBack: Uint8List(0));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(0));
      expect(v.expectedByte, equals(0));
      expect(v.gotByte, isNull);
      expect(v.gotLen, equals(0));
    });

    test('overrun (read-back longer) diverges at expectedLen, no expectedByte', () {
      final v = evaluateTransfer(expectedLen: 4, readBack: pattern(6));
      expect(v.ok, isFalse);
      expect(v.firstDivergenceOffset, equals(4));
      expect(v.expectedByte, isNull);
      expect(v.gotByte, equals(4 & 0xff));
      expect(v.gotLen, equals(6));
    });

    test('zero-length expectation with empty read-back is ok', () {
      final v = evaluateTransfer(expectedLen: 0, readBack: Uint8List(0));
      expect(v.ok, isTrue);
    });

    test('describe() summarizes a divergence as offset/bytes/lengths', () {
      final v = evaluateTransfer(expectedLen: 514, readBack: pattern(512));
      expect(
        v.describe(),
        equals('offset 512: expected 0x00 got -- (len 514 vs 512)'),
      );
    });
  });
}

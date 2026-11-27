import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanMode', () {
    test('has all expected values', () {
      expect(ScanMode.values, hasLength(3));
      expect(ScanMode.values, contains(ScanMode.balanced));
      expect(ScanMode.values, contains(ScanMode.lowLatency));
      expect(ScanMode.values, contains(ScanMode.lowPower));
    });
  });
}

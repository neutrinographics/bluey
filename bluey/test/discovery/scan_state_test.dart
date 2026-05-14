import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanState', () {
    test('has all five expected values', () {
      expect(ScanState.values, hasLength(5));
      expect(ScanState.values, contains(ScanState.stopped));
      expect(ScanState.values, contains(ScanState.starting));
      expect(ScanState.values, contains(ScanState.scanning));
      expect(ScanState.values, contains(ScanState.stopping));
      expect(ScanState.values, contains(ScanState.invalidated));
    });

    test('invalidated is distinct from stopped', () {
      expect(ScanState.invalidated, isNot(equals(ScanState.stopped)));
    });
  });
}

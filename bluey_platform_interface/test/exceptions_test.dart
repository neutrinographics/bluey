import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GattOperationTimeoutException', () {
    test('exposes the operation name and a default message', () {
      const e = GattOperationTimeoutException('writeCharacteristic');

      expect(e.operation, equals('writeCharacteristic'));
      expect(
        e.toString(),
        contains('writeCharacteristic'),
        reason: 'toString should mention the operation for log readability',
      );
    });

    test('is an Exception so it can be caught with on Exception', () {
      const e = GattOperationTimeoutException('readCharacteristic');
      expect(e, isA<Exception>());
    });

    test('two instances with the same operation are equal', () {
      const a = GattOperationTimeoutException('readCharacteristic');
      const b = GattOperationTimeoutException('readCharacteristic');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}

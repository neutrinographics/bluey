import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaleHandleException', () {
    test('extends BlueyException', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Server',
      );

      expect(exception, isA<BlueyException>());
    });

    test('carries triggeringState and instanceType', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.unauthorized,
        instanceType: 'Connection',
      );

      expect(exception.triggeringState, equals(BluetoothState.unauthorized));
      expect(exception.instanceType, equals('Connection'));
    });

    test('message identifies the instance type and triggering state', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Server',
      );

      expect(exception.message, contains('Server'));
      expect(exception.message, contains('off'));
    });

    test('action guides the caller to construct fresh', () {
      final exception = StaleHandleException(
        triggeringState: BluetoothState.off,
        instanceType: 'Connection',
      );

      expect(exception.action, contains('fresh'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey/src/shared/uuid.dart';
import 'package:bluey/src/gatt_client/well_known_uuids.dart';

void main() {
  group('BlueyException', () {
    test('is an Exception', () {
      final exception = BluetoothUnavailableException();
      expect(exception, isA<Exception>());
    });

    test('has message and action', () {
      final exception = BluetoothUnavailableException();
      expect(exception.message, isNotEmpty);
      expect(exception.action, isNotNull);
    });

    test('toString includes message', () {
      final exception = BluetoothDisabledException();
      expect(exception.toString(), contains('Bluetooth is turned off'));
    });
  });

  group('State Exceptions', () {
    test('BluetoothUnavailableException', () {
      final exception = BluetoothUnavailableException();
      expect(exception.message, contains('not available'));
    });

    test('BluetoothDisabledException', () {
      final exception = BluetoothDisabledException();
      expect(exception.message, contains('turned off'));
      expect(exception.action, contains('requestEnable'));
    });

    test('PermissionDeniedException with permissions list', () {
      final exception = PermissionDeniedException([
        'BLUETOOTH_SCAN',
        'BLUETOOTH_CONNECT',
      ]);
      expect(exception.message, contains('BLUETOOTH_SCAN'));
      expect(exception.message, contains('BLUETOOTH_CONNECT'));
      expect(exception.permissions, hasLength(2));
    });
  });

  group('Connection Exceptions', () {
    test('ConnectionException with reason', () {
      final deviceId = UUID.short(0x1234);
      final exception = ConnectionException(
        deviceId,
        ConnectionFailureReason.timeout,
      );

      expect(exception.deviceId, equals(deviceId));
      expect(exception.reason, equals(ConnectionFailureReason.timeout));
      expect(exception.message, contains('timeout'));
    });

    test('ConnectionException has action', () {
      final exception = ConnectionException(
        UUID.short(0x1234),
        ConnectionFailureReason.timeout,
      );
      expect(exception.action, isNotNull);
      expect(exception.action, contains('range'));
    });

    test('DisconnectedException with reason', () {
      final deviceId = UUID.short(0x1234);
      final exception = DisconnectedException(
        deviceId,
        DisconnectReason.linkLoss,
      );

      expect(exception.deviceId, equals(deviceId));
      expect(exception.reason, equals(DisconnectReason.linkLoss));
      expect(exception.message, contains('link'));
    });

    test('DisconnectedException has action', () {
      final exception = DisconnectedException(
        UUID.short(0x1234),
        DisconnectReason.linkLoss,
      );
      expect(exception.action, isNotNull);
      expect(exception.action, contains('Reconnect'));
    });
  });

  group('GATT Exceptions', () {
    test('ServiceNotFoundException', () {
      final serviceUuid = Services.heartRate;
      final exception = ServiceNotFoundException(serviceUuid);

      expect(exception.serviceUuid, equals(serviceUuid));
      expect(exception.message, contains('Service not found'));
    });

    test('ServiceNotFoundException has action', () {
      final exception = ServiceNotFoundException(Services.heartRate);
      expect(exception.action, isNotNull);
      expect(exception.action, contains('service'));
    });

    test('CharacteristicNotFoundException', () {
      final charUuid = UUID.short(0x2A37);
      final exception = CharacteristicNotFoundException(charUuid);

      expect(exception.characteristicUuid, equals(charUuid));
      expect(exception.message, contains('Characteristic not found'));
    });

    test('CharacteristicNotFoundException has action', () {
      final exception = CharacteristicNotFoundException(UUID.short(0x2A37));
      expect(exception.action, isNotNull);
      expect(exception.action, contains('characteristic'));
    });

    test('GattException with status', () {
      final exception = GattException(GattStatus.readNotPermitted);

      expect(exception.status, equals(GattStatus.readNotPermitted));
      expect(exception.message, contains('readNotPermitted'));
    });

    test('GattException has action', () {
      final exception = GattException(GattStatus.readNotPermitted);
      expect(exception.action, isNotNull);
    });

    test('OperationNotSupportedException', () {
      final exception = OperationNotSupportedException('write');

      expect(exception.operation, equals('write'));
      expect(exception.message, contains('write'));
      expect(exception.action, isNotNull);
    });
  });

  group('Server Exceptions', () {
    test('AdvertisingException with reason', () {
      final exception = AdvertisingException(
        AdvertisingFailureReason.dataTooBig,
      );

      expect(exception.reason, equals(AdvertisingFailureReason.dataTooBig));
      expect(exception.message, contains('dataTooBig'));
    });

    test('AdvertisingException has action', () {
      final exception = AdvertisingException(
        AdvertisingFailureReason.dataTooBig,
      );
      expect(exception.action, isNotNull);
    });
  });

  group('Platform Exceptions', () {
    test('UnsupportedOperationException', () {
      final exception = UnsupportedOperationException('requestMtu', 'iOS');

      expect(exception.operation, equals('requestMtu'));
      expect(exception.platform, equals('iOS'));
      expect(exception.message, contains('requestMtu'));
      expect(exception.message, contains('iOS'));
      expect(exception.action, contains('capabilities'));
    });
  });

  group('Enums', () {
    test('ConnectionFailureReason has all cases', () {
      expect(
        ConnectionFailureReason.values,
        contains(ConnectionFailureReason.timeout),
      );
      expect(
        ConnectionFailureReason.values,
        contains(ConnectionFailureReason.deviceNotFound),
      );
      expect(
        ConnectionFailureReason.values,
        contains(ConnectionFailureReason.unknown),
      );
    });

    test('DisconnectReason has all cases', () {
      expect(DisconnectReason.values, contains(DisconnectReason.requested));
      expect(DisconnectReason.values, contains(DisconnectReason.linkLoss));
    });

    test('GattStatus has all cases', () {
      expect(GattStatus.values, contains(GattStatus.success));
      expect(GattStatus.values, contains(GattStatus.readNotPermitted));
      expect(GattStatus.values, contains(GattStatus.writeNotPermitted));
    });

    test('AdvertisingFailureReason has all cases', () {
      expect(
        AdvertisingFailureReason.values,
        contains(AdvertisingFailureReason.dataTooBig),
      );
      expect(
        AdvertisingFailureReason.values,
        contains(AdvertisingFailureReason.notSupported),
      );
    });
  });
}

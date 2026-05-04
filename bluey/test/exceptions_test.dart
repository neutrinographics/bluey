import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey/src/shared/uuid.dart';
import 'package:bluey/src/gatt_client/well_known_uuids.dart';
import 'package:bluey/src/peer/server_id.dart';

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

  group('PeerNotFoundException', () {
    test('exposes expected id and timeout in message', () {
      final id = ServerId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final ex = PeerNotFoundException(id, const Duration(seconds: 5));
      expect(ex.expected, equals(id));
      expect(ex.timeout, const Duration(seconds: 5));
      expect(ex.toString(), contains('aaaaaaaa'));
    });

    test('is a BlueyException', () {
      expect(
        PeerNotFoundException(ServerId.generate(), const Duration(seconds: 1)),
        isA<BlueyException>(),
      );
    });
  });

  group('PeerIdentityMismatchException', () {
    test('exposes expected and actual ids', () {
      final expected = ServerId.generate();
      final actual = ServerId.generate();
      final ex = PeerIdentityMismatchException(expected, actual);
      expect(ex.expected, equals(expected));
      expect(ex.actual, equals(actual));
    });

    test('is a BlueyException', () {
      expect(
        PeerIdentityMismatchException(ServerId.generate(), ServerId.generate()),
        isA<BlueyException>(),
      );
    });
  });

  group('GattTimeoutException', () {
    test('exposes the operation name', () {
      const e = GattTimeoutException('writeCharacteristic');
      expect(e.operation, equals('writeCharacteristic'));
    });

    test('is a BlueyException so callers can pattern-match exhaustively', () {
      const e = GattTimeoutException('readCharacteristic');
      expect(e, isA<BlueyException>());
    });

    test('toString mentions the operation', () {
      const e = GattTimeoutException('discoverServices');
      expect(e.toString(), contains('discoverServices'));
    });

    test('has a remediation action', () {
      const e = GattTimeoutException('writeDescriptor');
      expect(e.action, isNotNull);
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

  group('BlueyPlatformException', () {
    test('exposes message, code, and cause', () {
      final cause = Exception('underlying');
      final e = BlueyPlatformException(
        'boom',
        code: 'widget-broke',
        cause: cause,
      );
      expect(e.message, 'boom');
      expect(e.code, 'widget-broke');
      expect(e.cause, same(cause));
    });

    test('code is optional and defaults to null', () {
      final e = BlueyPlatformException('boom');
      expect(e.code, isNull);
    });
  });

  group('RespondNotFoundException', () {
    test('extends BlueyException', () {
      const e = RespondNotFoundException('requestId 42');
      expect(e, isA<BlueyException>());
    });

    test('toString includes the operation context', () {
      const e = RespondNotFoundException('requestId 42 missing');
      expect(e.toString(), contains('RespondNotFoundException'));
    });

    test('exposes the message via the public field', () {
      const e = RespondNotFoundException('requestId 42 missing');
      expect(e.message, contains('requestId 42 missing'));
    });
  });
}

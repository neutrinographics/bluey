import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/gatt_repository.dart';

/// Implementation of [GattRepository] using the Bluey library.
class GattRepositoryImpl implements GattRepository {
  GattRepositoryImpl();

  @override
  Future<Uint8List> readCharacteristic(
    RemoteCharacteristic characteristic,
  ) async {
    return await characteristic.read();
  }

  @override
  Future<void> writeCharacteristic(
    RemoteCharacteristic characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) async {
    await characteristic.write(value, withResponse: withResponse);
  }

  @override
  Stream<Uint8List> subscribeToCharacteristic(
    RemoteCharacteristic characteristic,
  ) {
    return characteristic.notifications;
  }

  @override
  Future<Uint8List> readDescriptor(RemoteDescriptor descriptor) async {
    return await descriptor.read();
  }
}

import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// Abstract repository interface for characteristic and descriptor operations.
abstract class CharacteristicRepository {
  /// Reads the value of a characteristic.
  Future<Uint8List> readCharacteristic(RemoteCharacteristic characteristic);

  /// Writes a value to a characteristic.
  Future<void> writeCharacteristic(
    RemoteCharacteristic characteristic,
    Uint8List value, {
    bool withResponse = true,
  });

  /// Subscribes to notifications/indications from a characteristic.
  /// Returns a stream of values received from the characteristic.
  Stream<Uint8List> subscribeToCharacteristic(
    RemoteCharacteristic characteristic,
  );

  /// Reads the value of a descriptor.
  Future<Uint8List> readDescriptor(RemoteDescriptor descriptor);
}

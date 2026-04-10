import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../gatt_repository.dart';

/// Use case for reading a characteristic value.
class ReadCharacteristic {
  final GattRepository _repository;

  ReadCharacteristic(this._repository);

  /// Reads the value of the specified [characteristic].
  ///
  /// Returns the characteristic value as bytes.
  /// Throws an exception if the read fails or the characteristic
  /// doesn't support reading.
  Future<Uint8List> call(RemoteCharacteristic characteristic) async {
    return await _repository.readCharacteristic(characteristic);
  }
}

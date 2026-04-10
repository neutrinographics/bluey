import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../characteristic_repository.dart';

/// Use case for writing a value to a characteristic.
class WriteCharacteristic {
  final CharacteristicRepository _repository;

  WriteCharacteristic(this._repository);

  /// Writes [value] to the specified [characteristic].
  ///
  /// Set [withResponse] to true for write-with-response,
  /// or false for write-without-response.
  Future<void> call(
    RemoteCharacteristic characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) async {
    await _repository.writeCharacteristic(
      characteristic,
      value,
      withResponse: withResponse,
    );
  }
}

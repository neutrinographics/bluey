import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../gatt_repository.dart';

/// Use case for reading a descriptor value.
class ReadDescriptor {
  final GattRepository _repository;

  ReadDescriptor(this._repository);

  /// Reads the value of the specified [descriptor].
  ///
  /// Returns the descriptor value as bytes.
  Future<Uint8List> call(RemoteDescriptor descriptor) async {
    return await _repository.readDescriptor(descriptor);
  }
}

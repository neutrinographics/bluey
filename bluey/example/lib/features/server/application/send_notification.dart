import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for sending notifications to connected centrals.
class SendNotification {
  final ServerRepository _repository;

  SendNotification(this._repository);

  /// Sends a notification with [data] to all connected centrals
  /// for the specified [characteristicUuid].
  Future<void> call(UUID characteristicUuid, Uint8List data) async {
    await _repository.notify(characteristicUuid, data);
  }
}

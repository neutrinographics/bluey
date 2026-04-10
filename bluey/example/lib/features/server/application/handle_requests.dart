import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for observing and responding to read requests from centrals.
class ObserveReadRequests {
  final ServerRepository _repository;

  ObserveReadRequests(this._repository);

  /// Returns a stream of read requests from connected centrals.
  Stream<ReadRequest> call() {
    return _repository.readRequests;
  }

  /// Responds to a read request with the given value.
  Future<void> respond(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  }) async {
    await _repository.respondToRead(request, status: status, value: value);
  }
}

/// Use case for observing and responding to write requests from centrals.
class ObserveWriteRequests {
  final ServerRepository _repository;

  ObserveWriteRequests(this._repository);

  /// Returns a stream of write requests from connected centrals.
  Stream<WriteRequest> call() {
    return _repository.writeRequests;
  }

  /// Responds to a write request.
  Future<void> respond(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    await _repository.respondToWrite(request, status: status);
  }
}

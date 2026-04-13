import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'server.dart';
import 'uuid.dart';

/// Response status for GATT operations.
///
/// Used when responding to read or write requests from clients.
enum GattResponseStatus {
  /// Operation completed successfully.
  success,

  /// Read operation not permitted.
  readNotPermitted,

  /// Write operation not permitted.
  writeNotPermitted,

  /// Invalid offset for the attribute value.
  invalidOffset,

  /// Invalid attribute value length.
  invalidAttributeLength,

  /// Insufficient authentication for the operation.
  insufficientAuthentication,

  /// Insufficient encryption for the operation.
  insufficientEncryption,

  /// Request not supported.
  requestNotSupported,
}

/// A read request from a connected client.
///
/// When a client reads a characteristic value, a [ReadRequest] is emitted
/// on [Server.readRequests]. The server must respond using [Server.respondToRead].
@immutable
class ReadRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being read.
  final UUID characteristicId;

  /// The offset into the characteristic value.
  final int offset;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a read request.
  const ReadRequest({
    required this.client,
    required this.characteristicId,
    required this.offset,
    required this.internalRequestId,
  });
}

/// A write request from a connected client.
///
/// When a client writes to a characteristic, a [WriteRequest] is emitted
/// on [Server.writeRequests]. If [responseNeeded] is true, the server must
/// respond using [Server.respondToWrite].
@immutable
class WriteRequest {
  /// The client that initiated this request.
  final Client client;

  /// The characteristic being written.
  final UUID characteristicId;

  /// The value being written.
  final Uint8List value;

  /// The offset into the characteristic value.
  final int offset;

  /// Whether a response is needed.
  ///
  /// If true, the server must call [Server.respondToWrite].
  /// If false, this is a "write without response" operation.
  final bool responseNeeded;

  // Internal request ID for response correlation.
  // ignore: public_member_api_docs
  final int internalRequestId;

  /// Creates a write request.
  const WriteRequest({
    required this.client,
    required this.characteristicId,
    required this.value,
    required this.offset,
    required this.responseNeeded,
    required this.internalRequestId,
  });
}

import 'package:bluey/bluey.dart';

import '../domain/connection_repository.dart';

/// Use case for attempting to upgrade a raw [Connection] to a
/// [PeerConnection]. Returns `null` for non-peer devices.
class TryUpgrade {
  final ConnectionRepository _repository;

  TryUpgrade(this._repository);

  Future<PeerConnection?> call(Connection connection) async {
    return await _repository.tryUpgrade(connection);
  }
}

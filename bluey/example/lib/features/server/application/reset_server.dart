import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for resetting the server with a new identity.
class ResetServer {
  final ServerRepository _repository;

  ResetServer(this._repository);

  /// Disposes the current server and re-creates it with the given
  /// [identity].
  Future<Server?> call({required ServerId identity}) {
    return _repository.resetServer(identity: identity);
  }
}

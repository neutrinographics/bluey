import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for retrieving the active [Server] instance.
///
/// Used by the cubit to pass the [Server] directly to handlers that require
/// it (e.g. [StressServiceHandler]) rather than routing through individual
/// use cases for every server operation.
class GetServer {
  final ServerRepository _repository;

  GetServer(this._repository);

  /// Returns the active [Server] instance, or null if not supported.
  Server? call() => _repository.getServer();
}

import '../server_repository.dart';

/// Use case for disposing server resources.
class DisposeServer {
  final ServerRepository _repository;

  DisposeServer(this._repository);

  /// Releases all server resources.
  Future<void> call() async {
    await _repository.dispose();
  }
}

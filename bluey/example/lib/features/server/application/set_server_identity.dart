import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Use case for setting the server identity before initialisation.
class SetServerIdentity {
  final ServerRepository _repository;

  SetServerIdentity(this._repository);

  /// Sets the [ServerId] that will be used when the server is created.
  void call(ServerId identity) {
    _repository.setIdentity(identity);
  }
}

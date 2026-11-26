import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/value_objects/connection_parameters.dart';

/// How Connection reads and asks for the connection parameters of one link,
/// so the parameter session runs over a double and over the platform alike.
abstract interface class ParameterControl {
  /// The link's connection parameters as the radio holds them now.
  Future<Either<ConnectionFailure, ConnectionParameters>> parametersOf(
    LinkId link,
  );

  /// Asks the radio to time the link by [parameters]. The radio reports no
  /// change of its parameters, so a request it takes is all there is to know.
  Future<Either<ConnectionFailure, void>> request(
    LinkId link,
    ConnectionParameters parameters,
  );
}

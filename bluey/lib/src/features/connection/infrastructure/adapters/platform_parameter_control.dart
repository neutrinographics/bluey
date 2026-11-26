import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/domain/either.dart';
import '../../application/ports/parameter_control.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/link_operation.dart';
import '../../domain/value_objects/connection_interval.dart';
import '../../domain/value_objects/connection_parameters.dart';
import '../../domain/value_objects/peripheral_latency.dart';
import '../../domain/value_objects/supervision_timeout.dart';
import 'platform_failures.dart';

/// Connection's [ParameterControl] over [BlueyPlatform].
///
/// A platform that answers parameters outside the specification's ranges is
/// answered as an [UnexpectedPlatformFailure]: the value objects refuse
/// them, and the port promises an answer, never a throw.
final class PlatformParameterControl implements ParameterControl {
  const PlatformParameterControl(BlueyPlatform platform) : _platform = platform;

  final BlueyPlatform _platform;

  @override
  Future<Either<ConnectionFailure, ConnectionParameters>> parametersOf(
    LinkId link,
  ) async => (await answering(
    LinkOperation.readConnectionParameters,
    () => _platform.getConnectionParameters(link.value),
  )).flatMap(_parametersOf);

  @override
  Future<Either<ConnectionFailure, void>> request(
    LinkId link,
    ConnectionParameters parameters,
  ) => answering(
    LinkOperation.requestConnectionParameters,
    () => _platform.requestConnectionParameters(
      link.value,
      PlatformConnectionParameters(
        intervalMs: parameters.interval.milliseconds,
        latency: parameters.latency.events,
        timeoutMs: parameters.timeout.milliseconds,
      ),
    ),
  );
}

Either<ConnectionFailure, ConnectionParameters> _parametersOf(
  PlatformConnectionParameters answer,
) {
  try {
    return Right(
      ConnectionParameters(
        interval: ConnectionInterval(answer.intervalMs),
        latency: PeripheralLatency(answer.latency),
        timeout: SupervisionTimeout(answer.timeoutMs),
      ),
    );
  } on ArgumentError catch (error) {
    return Left(
      UnexpectedPlatformFailure(
        'connection parameters outside the specification: ${error.message}',
        cause: error,
      ),
    );
  }
}

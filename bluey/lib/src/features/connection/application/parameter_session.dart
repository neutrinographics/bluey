import '../../../shared/application/log.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_features.dart';
import '../domain/link_operation.dart';
import '../domain/value_objects/connection_interval.dart';
import '../domain/value_objects/connection_parameters.dart';
import '../domain/value_objects/peripheral_latency.dart';
import '../domain/value_objects/supervision_timeout.dart';
import 'check_before_asking.dart';
import 'link_session.dart';
import 'ports/parameter_control.dart';
import 'reported_value.dart';

/// One link's timing, and the request that changes it.
///
/// The radio reports no change of a link's parameters, so a request it takes
/// is held as the link's timing until another one is. On a platform that
/// cannot request parameters the port is never touched and the timing stays
/// an interval of 30 ms, a latency of 0 and a timeout of 4,000 ms.
final class ParameterSession {
  /// Reads the timing once, at once, unless the platform cannot request
  /// parameters.
  ParameterSession({
    required LinkSession session,
    required ParameterControl parameters,
    required LinkFeatures features,
    required Log log,
  }) : _session = session,
       _control = parameters,
       _supported = features.canRequestParameters,
       _held =
           features.canRequestParameters
               ? ReportedValue(
                 session: session,
                 initial: _defaults,
                 readFirst: () => parameters.parametersOf(session.link.id),
                 log: log,
                 failedReadLine: 'connection parameters read failed',
               )
               : ReportedValue.unreported(_defaults);

  static final ConnectionParameters _defaults = ConnectionParameters(
    interval: ConnectionInterval(30),
    latency: PeripheralLatency(0),
    timeout: SupervisionTimeout(4000),
  );

  final LinkSession _session;
  final ParameterControl _control;
  final bool _supported;
  final ReportedValue<ConnectionParameters> _held;

  /// The link's timing, as last read or granted.
  ///
  /// It is still answered after a plain disconnect; after a radio outage the
  /// outage is answered instead.
  Either<ConnectionFailure, ConnectionParameters> get parameters =>
      _check(LinkOperation.readConnectionParameters).map((_) => _held.value);

  /// Asks the radio to time the link by [parameters], held once it is
  /// granted; the link's end when it is not up.
  Future<Either<ConnectionFailure, void>> request(
    ConnectionParameters parameters,
  ) => _check(LinkOperation.requestConnectionParameters).flatMapAsync(
    (_) async => (await _session.whileUp(
      () => _control.request(_session.link.id, parameters),
      orEnd: LinkHadEnded.new,
    )).map((_) => _held.take(parameters)),
  );

  Either<ConnectionFailure, void> _check(LinkOperation operation) =>
      checkBeforeAsking(
        _session.link,
        operation: operation,
        supported: _supported,
      );
}

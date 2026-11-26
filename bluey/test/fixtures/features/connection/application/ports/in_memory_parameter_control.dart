import 'dart:async';

import 'package:bluey/src/features/connection/application/ports/parameter_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_interval.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_parameters.dart';
import 'package:bluey/src/features/connection/domain/value_objects/peripheral_latency.dart';
import 'package:bluey/src/features/connection/domain/value_objects/supervision_timeout.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'parameter_control_contract.dart';

/// A radio in memory that times links, so the parameter session can be
/// tested without a platform.
///
/// It is its own [ParameterControlHarness], and adds what the session's
/// tests need: reads held back until told to answer, failures told by hand,
/// and what was asked of it.
class InMemoryParameterControl
    implements ParameterControl, ParameterControlHarness {
  final Map<LinkId, ConnectionParameters> _answers = {};
  final List<(LinkOperation, LinkId)> _asked = [];
  final List<ConnectionParameters> _requests = [];
  final Map<LinkOperation, ConnectionFailure> _nextFailures = {};
  Completer<void>? _heldReads;

  @override
  ParameterControl get parameters => this;

  @override
  LinkId get link => const LinkId('AA:BB:CC:DD:EE:01');

  /// Everything asked of the port, with its link, in order.
  List<(LinkOperation, LinkId)> get asked => List.unmodifiable(_asked);

  /// The parameters every request asked for, in order.
  List<ConnectionParameters> get requests => List.unmodifiable(_requests);

  @override
  Future<Either<ConnectionFailure, ConnectionParameters>> parametersOf(
    LinkId link,
  ) async {
    _asked.add((LinkOperation.readConnectionParameters, link));
    final failure = _nextFailures.remove(
      LinkOperation.readConnectionParameters,
    );
    final held = _heldReads;
    if (held != null) await held.future;
    if (failure != null) return Left(failure);
    return Right(_answers[link] ?? _radioDefault);
  }

  @override
  Future<Either<ConnectionFailure, void>> request(
    LinkId link,
    ConnectionParameters parameters,
  ) async {
    _asked.add((LinkOperation.requestConnectionParameters, link));
    _requests.add(parameters);
    final failure = _nextFailures.remove(
      LinkOperation.requestConnectionParameters,
    );
    if (failure != null) return Left(failure);
    return const Right(null);
  }

  /// A read of [link]'s connection parameters answers [parameters].
  void answer(LinkId link, ConnectionParameters parameters) =>
      _answers[link] = parameters;

  /// The next [operation] answers [failure].
  void failNext(LinkOperation operation, ConnectionFailure failure) =>
      _nextFailures[operation] = failure;

  /// Reads wait until [answerHeldReads], so a test can let a request or the
  /// link's end come first.
  void holdReads() => _heldReads = Completer<void>();

  /// Lets every held read answer.
  void answerHeldReads() {
    _heldReads?.complete();
    _heldReads = null;
  }

  @override
  void answerReads(ConnectionParameters parameters) => answer(link, parameters);

  @override
  void timeOutNextRead() => failNext(
    LinkOperation.readConnectionParameters,
    const OperationTimedOut(LinkOperation.readConnectionParameters),
  );

  @override
  void rejectNextRequest(int status) => failNext(
    LinkOperation.requestConnectionParameters,
    OperationRejected(LinkOperation.requestConnectionParameters, status),
  );
}

final _radioDefault = ConnectionParameters(
  interval: ConnectionInterval(30),
  latency: PeripheralLatency(0),
  timeout: SupervisionTimeout(4000),
);

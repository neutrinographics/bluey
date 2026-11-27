import 'package:bluey/src/features/connection/application/ports/parameter_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_interval.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_parameters.dart';
import 'package:bluey/src/features/connection/domain/value_objects/peripheral_latency.dart';
import 'package:bluey/src/features/connection/domain/value_objects/supervision_timeout.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [parameterControlContract] needs from the
/// [ParameterControl] it holds to account: a link that is up, and the ways
/// to make its radio answer each way the contract describes.
abstract class ParameterControlHarness {
  /// The port under contract.
  ParameterControl get parameters;

  /// A link that is up.
  LinkId get link;

  /// A read of the link's connection parameters answers [parameters].
  void answerReads(ConnectionParameters parameters);

  /// The next read of the connection parameters is not answered in time.
  void timeOutNextRead();

  /// The next request is rejected with [status].
  void rejectNextRequest(int status);
}

/// The promises every [ParameterControl] keeps, so a unit tested over the
/// double behaves the same over the platform.
void parameterControlContract(
  String name,
  Future<ParameterControlHarness> Function() create,
) {
  group(name, () {
    late ParameterControlHarness h;
    final brisk = ConnectionParameters(
      interval: ConnectionInterval(15),
      latency: PeripheralLatency(4),
      timeout: SupervisionTimeout(2000),
    );

    setUp(() async => h = await create());

    test('answers the parameters', () async {
      // arrange
      h.answerReads(brisk);

      // act
      final answer = await h.parameters.parametersOf(h.link);

      // assert
      expect(answer, Right<ConnectionFailure, ConnectionParameters>(brisk));
    });

    test('a failed read answers the failure', () async {
      // arrange
      h.timeOutNextRead();

      // act
      final answer = await h.parameters.parametersOf(h.link);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, ConnectionParameters>(
          OperationTimedOut(LinkOperation.readConnectionParameters),
        ),
      );
    });

    test('a request answers success', () async {
      // act
      final answer = await h.parameters.request(h.link, brisk);

      // assert
      expect(answer, const Right<ConnectionFailure, void>(null));
    });

    test('a rejected request answers OperationRejected with its '
        'status', () async {
      // arrange
      h.rejectNextRequest(137);

      // act
      final answer = await h.parameters.request(h.link, brisk);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, void>(
          OperationRejected(LinkOperation.requestConnectionParameters, 137),
        ),
      );
    });
  });
}

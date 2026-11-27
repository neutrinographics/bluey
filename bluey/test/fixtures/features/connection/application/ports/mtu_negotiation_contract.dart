import 'package:bluey/src/features/connection/application/ports/mtu_negotiation.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/features/connection/domain/value_objects/write_payload_limit.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a run of [mtuNegotiationContract] needs from the [MtuNegotiation] it
/// holds to account: a link that is up, and the ways to make its peer answer
/// each way the contract describes.
abstract class MtuNegotiationHarness {
  /// The port under contract.
  MtuNegotiation get negotiation;

  /// A link that is up.
  LinkId get link;

  /// The peer settles on no more than [mtu].
  void settleAt(int mtu);

  /// The next request is rejected with [status].
  void rejectNext(int status);

  /// The next request is not answered in time.
  void timeOutNext();

  /// The next payload limit read is rejected with [status].
  void rejectNextLimitRead(int status);

  /// One write with a response carries [withResponse] bytes, and one
  /// without carries [withoutResponse].
  void limitWrites({required int withResponse, required int withoutResponse});
}

/// The promises every [MtuNegotiation] keeps, so a unit tested over the
/// double behaves the same over the platform.
void mtuNegotiationContract(
  String name,
  Future<MtuNegotiationHarness> Function() create,
) {
  group(name, () {
    late MtuNegotiationHarness h;

    setUp(() async => h = await create());

    test('answers the MTU that was asked for', () async {
      // act
      final answer = await h.negotiation.request(h.link, Mtu(247));

      // assert
      expect(answer, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(247)));
    });

    test('answers the lower MTU the peer settles on', () async {
      // arrange
      h.settleAt(185);

      // act
      final answer = await h.negotiation.request(h.link, Mtu(247));

      // assert
      expect(answer, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
    });

    test(
      'a rejected request answers OperationRejected with its status',
      () async {
        // arrange
        h.rejectNext(133);

        // act
        final answer = await h.negotiation.request(h.link, Mtu(247));

        // assert
        expect(
          answer,
          const Left<ConnectionFailure, Mtu>(
            OperationRejected(LinkOperation.negotiateMtu, 133),
          ),
        );
      },
    );

    test('a request that times out answers OperationTimedOut', () async {
      // arrange
      h.timeOutNext();

      // act
      final answer = await h.negotiation.request(h.link, Mtu(247));

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, Mtu>(
          OperationTimedOut(LinkOperation.negotiateMtu),
        ),
      );
    });

    test('answers the write payload limit for each kind of write', () async {
      // arrange
      h.limitWrites(withResponse: 244, withoutResponse: 182);

      // act
      final withResponse = await h.negotiation.writePayloadLimit(
        h.link,
        withResponse: true,
      );
      final withoutResponse = await h.negotiation.writePayloadLimit(
        h.link,
        withResponse: false,
      );

      // assert
      expect(
        [withResponse, withoutResponse],
        [
          Right<ConnectionFailure, WritePayloadLimit>(
            WritePayloadLimit.fromPlatform(244),
          ),
          Right<ConnectionFailure, WritePayloadLimit>(
            WritePayloadLimit.fromPlatform(182),
          ),
        ],
      );
    });

    test('a rejected payload limit read answers OperationRejected with its '
        'status', () async {
      // arrange
      h.rejectNextLimitRead(8);

      // act
      final answer = await h.negotiation.writePayloadLimit(
        h.link,
        withResponse: true,
      );

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, WritePayloadLimit>(
          OperationRejected(LinkOperation.readWritePayloadLimit, 8),
        ),
      );
    });
  });
}

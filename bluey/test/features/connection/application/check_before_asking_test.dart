import 'package:bluey/src/features/connection/application/check_before_asking.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/src/shared/domain/radio_outage.dart';

const _device = DeviceAddress('AA:BB:CC:DD:EE:01');
final _at = DateTime.utc(2026, 11, 26, 10);

Link _upLink() =>
    Link.begin(
      device: _device,
      at: _at,
    ).link.on(const OpenSucceeded(LinkId('link-1')), at: _at).link;

void main() {
  test('an up link with the feature answers nothing in the way', () {
    // act
    final checked = checkBeforeAsking(
      _upLink(),
      operation: LinkOperation.negotiateMtu,
    );

    // assert
    expect(checked, const Right<ConnectionFailure, void>(null));
  });

  test('a platform without the feature answers FeatureUnsupported', () {
    // act
    final checked = checkBeforeAsking(
      _upLink(),
      operation: LinkOperation.negotiateMtu,
      supported: false,
    );

    // assert
    expect(
      checked,
      const Left<ConnectionFailure, void>(
        FeatureUnsupported(LinkOperation.negotiateMtu),
      ),
    );
  });

  test('a link a radio outage ended answers the outage before a missing '
      'feature', () {
    // arrange
    final ended =
        _upLink().on(const RadioOutageBegan(RadioOutage.off), at: _at).link;

    // act
    final checked = checkBeforeAsking(
      ended,
      operation: LinkOperation.negotiateMtu,
      supported: false,
    );

    // assert
    expect(
      checked,
      const Left<ConnectionFailure, void>(
        LinkHadEnded(EndedByRadioOutage(RadioOutage.off)),
      ),
    );
  });

  test('a link that dropped is not this check\'s to refuse', () {
    // arrange
    final dropped =
        _upLink()
            .on(const RadioReported(LinkReport.disconnected), at: _at)
            .link;

    // act
    final checked = checkBeforeAsking(
      dropped,
      operation: LinkOperation.negotiateMtu,
    );

    // assert
    expect(checked, const Right<ConnectionFailure, void>(null));
  });
}

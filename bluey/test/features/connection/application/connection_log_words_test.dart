import 'package:bluey/src/features/connection/application/connection_log_words.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/link_phase.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the context is the one apps filter on', () {
    // assert
    expect(connectionLogContext, 'bluey.connection');
  });

  test('the GATT context is the one apps filter on', () {
    // assert
    expect(gattLogContext, 'bluey.gatt');
  });

  group('stateWordOf', () {
    // (name, phase, the word logs have always written)
    final rows = <(String, LinkPhase, String)>[
      ('linked', const Linked(), 'ConnectionState.linked'),
      ('ready', const Ready(), 'ConnectionState.ready'),
      (
        'closing',
        const Closing(returnTo: Linked(), by: ClosingBy.radio),
        'ConnectionState.disconnecting',
      ),
      (
        'ended on request',
        const Ended(EndedOnRequest()),
        'ConnectionState.disconnected',
      ),
      (
        'ended by a drop',
        const Ended(EndedByDrop()),
        'ConnectionState.disconnected',
      ),
      (
        'ended by an outage',
        const Ended(EndedByRadioOutage(RadioOutage.unknown)),
        'ConnectionState.invalidated',
      ),
    ];

    for (final (name, phase, word) in rows) {
      test('a link $name is logged as $word', () {
        // act
        final logged = stateWordOf(phase);

        // assert
        expect(logged, word);
      });
    }
  });

  group('operationWordOf', () {
    // (operation, the word logs and exception messages have always written)
    final rows = <(LinkOperation, String)>[
      (LinkOperation.open, 'connect'),
      (LinkOperation.close, 'disconnect'),
      (LinkOperation.negotiateMtu, 'requestMtu'),
      (LinkOperation.readWritePayloadLimit, 'getMaximumWriteLength'),
      (LinkOperation.readSignalStrength, 'readRssi'),
    ];

    for (final (operation, word) in rows) {
      test('${operation.name} is worded $word', () {
        // act
        final worded = operationWordOf(operation);

        // assert
        expect(worded, word);
      });
    }
  });

  group('failureCodeOf', () {
    // (failure, the code logs have always written: its class name on main)
    final rows = <(ConnectionFailure, String)>[
      (const ConnectFailed(ConnectFailureReason.timeout), 'ConnectFailed'),
      (const LinkHadEnded(EndedByDrop()), 'LinkEnded'),
      (const RadioUnavailable(), 'RadioUnavailable'),
      (const PermissionMissing('bluetoothConnect'), 'PermissionMissing'),
      (const OperationTimedOut(LinkOperation.open), 'OperationTimedOut'),
      (const OperationRejected(LinkOperation.close, 133), 'OperationRejected'),
      (const UnexpectedPlatformFailure('boom'), 'UnexpectedPlatformFailure'),
      (
        const FeatureUnsupported(LinkOperation.negotiateMtu),
        'FeatureUnsupported',
      ),
      (MtuAboveMaximum(requested: Mtu(248), maximum: 247), 'MtuAboveMaximum'),
    ];

    for (final (failure, code) in rows) {
      test('$code is the code of ${failure.message}', () {
        // act
        final logged = failureCodeOf(failure);

        // assert
        expect(logged, code);
      });
    }
  });
}

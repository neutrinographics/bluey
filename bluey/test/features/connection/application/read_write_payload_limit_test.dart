import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/read_write_payload_limit.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/write_payload_limit.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_mtu_negotiation.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  late InMemoryLinks links;
  late InMemoryMtuNegotiation negotiation;
  late RecordingLog log;
  late LinkSession session;
  late ReadWritePayloadLimit read;

  setUp(() async {
    links = InMemoryLinks();
    negotiation =
        InMemoryMtuNegotiation()
          ..limitWrites(withResponse: 244, withoutResponse: 182);
    log = RecordingLog();
    session = await upSession(links, device);
    read = ReadWritePayloadLimit(
      negotiation: negotiation,
      log: log,
      now: DateTime.now,
    );
  });

  test('answers the reading', () async {
    // act
    final withResponse = await read.run(session, withResponse: true);
    final withoutResponse = await read.run(session, withResponse: false);

    // assert
    expect(
      [withResponse, withoutResponse],
      [
        Right<ConnectionFailure, WritePayloadLimit>(WritePayloadLimit(244)),
        Right<ConnectionFailure, WritePayloadLimit>(WritePayloadLimit(182)),
      ],
    );
    expect(negotiation.limitReads, [
      (session.link.id, true),
      (session.link.id, false),
    ]);
  });

  test('answers the end of a link that is not up, and asks nothing', () async {
    // arrange
    links.drop(device);
    await pumpEventQueue();

    // act
    final answer = await read.run(session, withResponse: true);

    // assert
    expect(
      answer,
      const Left<ConnectionFailure, WritePayloadLimit>(
        LinkHadEnded(EndedByDrop()),
      ),
    );
    expect(negotiation.limitReads, isEmpty);
    expect(log.records, isEmpty);
  });

  test('logs start, complete and failed as the GATT log does', () async {
    // arrange
    await read.run(session, withResponse: true);
    negotiation.failNextLimitRead(
      const OperationRejected(LinkOperation.readWritePayloadLimit, 8),
    );

    // act
    await read.run(session, withResponse: false);

    // assert
    expect(
      log.records.map(
        (r) => (r.level, r.context, r.message, r.data['op'], r.data['detail']),
      ),
      [
        (
          BlueyLogLevel.debug,
          'bluey.gatt',
          'getMaximumWriteLength start',
          'getMaximumWriteLength',
          'withResponse=true',
        ),
        (
          BlueyLogLevel.debug,
          'bluey.gatt',
          'getMaximumWriteLength complete',
          'getMaximumWriteLength',
          'withResponse=true, limit=244',
        ),
        (
          BlueyLogLevel.debug,
          'bluey.gatt',
          'getMaximumWriteLength start',
          'getMaximumWriteLength',
          'withResponse=false',
        ),
        (
          BlueyLogLevel.error,
          'bluey.gatt',
          'getMaximumWriteLength failed',
          'getMaximumWriteLength',
          'withResponse=false',
        ),
      ],
    );
    expect(log.records.last.errorCode, 'OperationRejected');
    expect(log.records.last.data['status'], 8);
  });
}

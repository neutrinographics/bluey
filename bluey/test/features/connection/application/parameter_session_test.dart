import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/features/connection/application/parameter_session.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_interval.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_parameters.dart';
import 'package:bluey/src/features/connection/domain/value_objects/peripheral_latency.dart';
import 'package:bluey/src/features/connection/domain/value_objects/supervision_timeout.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_links.dart';
import '../../../fixtures/features/connection/application/ports/in_memory_parameter_control.dart';
import '../../../fixtures/features/connection/application/up_session.dart';
import '../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

const noParameters = LinkFeatures(
  canBond: true,
  canRequestPhy: true,
  canRequestParameters: false,
  canRequestMtu: true,
  maxMtu: 517,
);

ConnectionParameters timing(double interval, int latency, int timeout) =>
    ConnectionParameters(
      interval: ConnectionInterval(interval),
      latency: PeripheralLatency(latency),
      timeout: SupervisionTimeout(timeout),
    );

final defaults = timing(30, 0, 4000);
final read = timing(45, 2, 6000);
final asked = timing(15, 4, 2000);

void main() {
  late InMemoryLinks links;
  late InMemoryParameterControl port;
  late RecordingLog log;
  late LinkSession session;

  ParameterSession parametersOver({
    LinkFeatures features = unlimitedLinkFeatures,
  }) => ParameterSession(
    session: session,
    parameters: port,
    features: features,
    log: log,
  );

  void expectParameters(ParameterSession it, ConnectionParameters expected) =>
      expect(
        it.parameters,
        Right<ConnectionFailure, ConnectionParameters>(expected),
      );

  setUp(() async {
    links = InMemoryLinks();
    port = InMemoryParameterControl();
    log = RecordingLog();
    session = await upSession(links, device);
  });

  test('holds 30 ms, 0 and 4,000 ms until the first read answers', () {
    // arrange
    port
      ..holdReads()
      ..answer(session.link.id, read);

    // act
    final parameters = parametersOver();

    // assert
    expectParameters(parameters, defaults);
  });

  test('the first read sets the parameters', () async {
    // arrange
    port.answer(session.link.id, read);

    // act
    final parameters = parametersOver();
    await pumpEventQueue();

    // assert
    expectParameters(parameters, read);
    expect(port.asked, [
      (LinkOperation.readConnectionParameters, session.link.id),
    ]);
  });

  test('a request that succeeds holds what was asked for', () async {
    // arrange
    port.answer(session.link.id, read);
    final parameters = parametersOver();
    await pumpEventQueue();

    // act
    final requested = await parameters.request(asked);

    // assert
    expect(requested, const Right<ConnectionFailure, void>(null));
    expectParameters(parameters, asked);
    expect(port.requests, [asked]);
    expect(port.asked.last, (
      LinkOperation.requestConnectionParameters,
      session.link.id,
    ));
    expect(log.records, isEmpty);
  });

  test('a failed request keeps the parameters it had', () async {
    // arrange
    port.answer(session.link.id, read);
    final parameters = parametersOver();
    await pumpEventQueue();
    port.failNext(
      LinkOperation.requestConnectionParameters,
      const OperationRejected(LinkOperation.requestConnectionParameters, 137),
    );

    // act
    final requested = await parameters.request(asked);

    // assert
    expect(
      requested,
      const Left<ConnectionFailure, void>(
        OperationRejected(LinkOperation.requestConnectionParameters, 137),
      ),
    );
    expectParameters(parameters, read);
    expect(log.records, isEmpty);
  });

  test('a first read that answers after a successful request does not '
      'replace it', () async {
    // arrange
    port
      ..holdReads()
      ..answer(session.link.id, read);
    final parameters = parametersOver();
    await parameters.request(asked);

    // act
    port.answerHeldReads();
    await pumpEventQueue();

    // assert
    expectParameters(parameters, asked);
  });

  test('a first read that answers after the link ended is ignored', () async {
    // arrange
    port
      ..holdReads()
      ..answer(session.link.id, read);
    final parameters = parametersOver();
    links.drop(device);
    await pumpEventQueue();

    // act
    port.answerHeldReads();
    await pumpEventQueue();

    // assert
    expectParameters(parameters, defaults);
  });

  test('a failed first read is logged and the default stays', () async {
    // arrange
    port.failNext(
      LinkOperation.readConnectionParameters,
      const OperationTimedOut(LinkOperation.readConnectionParameters),
    );

    // act
    final parameters = parametersOver();
    await pumpEventQueue();

    // assert
    expectParameters(parameters, defaults);
    expect(
      log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [
        (
          BlueyLogLevel.warn,
          'bluey.connection',
          'connection parameters read failed',
          null,
        ),
      ],
    );
    expect(log.records.single.data, {
      'deviceId': 'AA:BB:CC:DD:EE:01',
      'exception': 'OperationTimedOut',
    });
  });

  test(
    'a first read that fails after the link ended is still logged',
    () async {
      // arrange
      port
        ..holdReads()
        ..failNext(
          LinkOperation.readConnectionParameters,
          const OperationRejected(LinkOperation.readConnectionParameters, 133),
        );
      parametersOver();
      links.drop(device);
      await pumpEventQueue();

      // act
      port.answerHeldReads();
      await pumpEventQueue();

      // assert
      expect(log.records.map((r) => r.message), [
        'connection parameters read failed',
      ]);
      expect(log.records.single.data, {
        'deviceId': 'AA:BB:CC:DD:EE:01',
        'exception': 'OperationRejected',
      });
    },
  );

  test('a platform that cannot request parameters is never asked', () async {
    // arrange
    final parameters = parametersOver(features: noParameters);
    await pumpEventQueue();

    // act
    final held = parameters.parameters;
    final requested = await parameters.request(asked);

    // assert
    expect(port.asked, isEmpty);
    expect(log.records, isEmpty);
    expect(
      held,
      const Left<ConnectionFailure, ConnectionParameters>(
        FeatureUnsupported(LinkOperation.readConnectionParameters),
      ),
    );
    expect(
      requested,
      const Left<ConnectionFailure, void>(
        FeatureUnsupported(LinkOperation.requestConnectionParameters),
      ),
    );
  });

  test('after a plain disconnect the parameters are still answered, and a '
      'request answers the end', () async {
    // arrange
    port.answer(session.link.id, read);
    final parameters = parametersOver();
    await pumpEventQueue();
    await session.disconnect();

    // act
    final requested = await parameters.request(asked);

    // assert
    expectParameters(parameters, read);
    expect(
      requested,
      const Left<ConnectionFailure, void>(LinkHadEnded(EndedOnRequest())),
    );
    expect(port.requests, isEmpty);
  });

  test('after a radio outage both answer the outage', () async {
    // arrange
    final parameters = parametersOver();
    await pumpEventQueue();
    links.outage(RadioOutage.off);
    await pumpEventQueue();

    // act
    final held = parameters.parameters;
    final requested = await parameters.request(asked);

    // assert
    const outage = LinkHadEnded(EndedByRadioOutage(RadioOutage.off));
    expect(held, const Left<ConnectionFailure, ConnectionParameters>(outage));
    expect(requested, const Left<ConnectionFailure, void>(outage));
    expect(port.requests, isEmpty);
  });
}

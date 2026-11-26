import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fakes/test_helpers.dart';
import '../../fixtures/either_results.dart';

/// Every link fact on, so no refusal below comes from a missing feature.
const android = platform.Capabilities(
  platformKind: platform.PlatformKind.android,
  canRequestMtu: true,
  maxMtu: 517,
  canBond: true,
  canRequestPhy: true,
  canRequestConnectionParameters: true,
);

const deviceId = TestDeviceIds.device1;

final parameters = ConnectionParameters(
  interval: ConnectionInterval(45),
  latency: PeripheralLatency(2),
  timeout: SupervisionTimeout(6000),
);

Device deviceFor(String address) =>
    Device(address: DeviceAddress(address), name: 'Test Device');

/// The fake, recording which link facts it was asked for and able to hold
/// the first read of a link's connection parameters back.
final class AskedFake extends FakeBlueyPlatform {
  AskedFake({super.capabilities});

  final List<String> asked = [];
  Completer<void>? heldParameterRead;

  @override
  Future<platform.PlatformBondState> getBondState(String deviceId) {
    asked.add('getBondState');
    return super.getBondState(deviceId);
  }

  @override
  Stream<platform.PlatformBondState> bondStateStream(String deviceId) {
    asked.add('bondStateStream');
    return super.bondStateStream(deviceId);
  }

  @override
  Future<({platform.PlatformPhy tx, platform.PlatformPhy rx})> getPhy(
    String deviceId,
  ) {
    asked.add('getPhy');
    return super.getPhy(deviceId);
  }

  @override
  Stream<({platform.PlatformPhy tx, platform.PlatformPhy rx})> phyStream(
    String deviceId,
  ) {
    asked.add('phyStream');
    return super.phyStream(deviceId);
  }

  @override
  Future<platform.PlatformConnectionParameters> getConnectionParameters(
    String deviceId,
  ) async {
    asked.add('getConnectionParameters');
    final held = heldParameterRead;
    if (held != null) await held.future;
    return super.getConnectionParameters(deviceId);
  }
}

void main() {
  group('over a Bluey on Android', () {
    late AskedFake fake;
    late Bluey bluey;
    late Connection connection;
    late List<BlueyLogEvent> logs;

    Future<void> connectOn(AskedFake platformFake) async {
      fake = platformFake;
      platform.BlueyPlatform.instance = fake;
      bluey = await Bluey.create();
      logs = [];
      bluey.logEvents.listen(logs.add);
      fake.simulatePeripheral(id: deviceId, name: 'Test Device');
      connection = await bluey.connect(deviceFor(deviceId));
      await pumpEventQueue();
    }

    tearDown(() async {
      await bluey.dispose();
      await fake.dispose();
    });

    group('a reading in flight', () {
      test('a Service Changed event does not fail a reading or an MTU '
          'request in flight', () {
        fakeAsync((async) {
          // arrange
          unawaited(connectOn(AskedFake(capabilities: android)));
          async.flushMicrotasks();
          fake.operationLatency = const Duration(seconds: 1);
          final rssi = connection.readRssi();
          final mtu = connection.android!.requestMtu(Mtu(247));
          final limit = connection.maxWritePayload(withResponse: true);
          async.elapse(const Duration(milliseconds: 500));

          expect(connection.state, ConnectionState.linked);

          // act
          fake.simulateServiceChange(deviceId);
          async.elapse(const Duration(seconds: 1));

          // assert
          expect(resultOf(rssi), isA<int>());
          expect(resultOf(mtu), Mtu(247));
          expect(resultOf(limit), isA<WritePayloadLimit>());
          expect(connection.state, ConnectionState.ready);
        });
      });

      test('a drop fails a reading in flight at once, with linkLoss', () {
        fakeAsync((async) {
          // arrange
          unawaited(connectOn(AskedFake(capabilities: android)));
          async.flushMicrotasks();
          fake.operationLatency = const Duration(seconds: 1);
          Object? failure;
          connection.readRssi().catchError((Object error) {
            failure = error;
            return 0;
          }).ignore();
          async.elapse(const Duration(milliseconds: 500));
          expect(connection.state, ConnectionState.linked);

          // act
          fake.simulateDisconnection(deviceId);
          async.elapse(const Duration(milliseconds: 100));

          // assert
          expect(
            failure,
            isA<DisconnectedException>().having(
              (e) => e.reason,
              'reason',
              DisconnectReason.linkLoss,
            ),
          );
          expect(connection.state, ConnectionState.disconnected);
          async.elapse(const Duration(seconds: 1));
        });
      });
    });

    group('a rejected operation', () {
      for (final (name, op, ask)
          in <(String, FakeOp, Future<Object?> Function(Connection))>[
            (
              'requestMtu',
              FakeOp.requestMtu,
              (c) => c.android!.requestMtu(Mtu(247)),
            ),
            ('readRssi', FakeOp.readRssi, (c) => c.readRssi()),
            ('bond', FakeOp.bond, (c) => c.android!.bond()),
            (
              'requestPhy',
              FakeOp.requestPhy,
              (c) => c.android!.requestPhy(txPhy: Phy.le2m),
            ),
            (
              'requestConnectionParameters',
              FakeOp.requestConnectionParameters,
              (c) => c.android!.requestConnectionParameters(parameters),
            ),
          ]) {
        test('$name rejected with status 0x80 reads as rejected, and the '
            'Connection stays connected', () async {
          // arrange
          await connectOn(AskedFake(capabilities: android));
          fake.enqueueFault(
            op,
            platform.GattOperationStatusFailedException(name, 0x80),
          );

          // act
          final asking = ask(connection);

          // assert
          await expectLater(
            asking,
            throwsA(
              isA<GattOperationFailedException>().having(
                (e) => e.status,
                'status',
                0x80,
              ),
            ),
          );
          expect(connection.state, ConnectionState.linked);
        });
      }
    });

    group('the log', () {
      Matcher failedFirstRead(String message, String code) =>
          isA<BlueyLogEvent>()
              .having((e) => e.level, 'level', BlueyLogLevel.warn)
              .having((e) => e.context, 'context', 'bluey.connection')
              .having((e) => e.message, 'message', message)
              .having((e) => e.data, 'data', {
                'deviceId': deviceId,
                'exception': code,
              });

      for (final (message, op) in [
        ('bond state read failed', FakeOp.getBondState),
        ('phy read failed', FakeOp.getPhy),
        ('connection parameters read failed', FakeOp.getConnectionParameters),
      ]) {
        test('a failed first read is logged once, as "$message"', () async {
          // arrange
          final failing = AskedFake(capabilities: android)..enqueueFault(
            op,
            const platform.GattOperationTimeoutException('read'),
          );

          // act
          await connectOn(failing);

          // assert
          expect(logs.where((e) => e.message == message), [
            failedFirstRead(message, 'OperationTimedOut'),
          ]);
        });
      }

      test('a failed readRssi logs the type of the failure', () async {
        // arrange
        await connectOn(AskedFake(capabilities: android));
        fake.enqueueFault(
          FakeOp.readRssi,
          const platform.GattOperationTimeoutException('readRssi'),
        );

        // act
        await expectLater(
          connection.readRssi(),
          throwsA(isA<GattTimeoutException>()),
        );
        await pumpEventQueue();

        // assert
        final failed = logs.singleWhere((e) => e.message == 'readRssi failed');
        expect(failed.errorCode, 'OperationTimedOut');
        expect(failed.data['exception'], 'OperationTimedOut');
      });
    });

    group('the first reads', () {
      test('a failed first bond read leaves bondState at none and connect() '
          'succeeds', () async {
        // arrange
        final failing = AskedFake(capabilities: android)
          ..enqueueFault(FakeOp.getBondState, StateError('the radio refused'));

        // act
        await connectOn(failing);

        // assert
        expect(connection.state, ConnectionState.linked);
        expect(connection.android!.bondState, BondState.none);
        expect(
          logs.where((e) => e.level == BlueyLogLevel.warn).map((e) => e.data),
          [
            {'deviceId': deviceId, 'exception': 'UnexpectedPlatformFailure'},
          ],
        );
      });

      test('a first parameters read that answers late does not overwrite '
          'parameters a request was granted', () async {
        // arrange
        final holding = AskedFake(capabilities: android)
          ..heldParameterRead = Completer<void>();
        await connectOn(holding);
        await connection.android!.requestConnectionParameters(parameters);

        // act
        holding.heldParameterRead!.complete();
        await pumpEventQueue();

        // assert
        expect(connection.android!.connectionParameters, parameters);
      });

      test('connecting on a kind that is neither Android nor iOS asks the '
          'platform for no bond state, PHY or parameters', () async {
        // act
        await connectOn(
          AskedFake(
            capabilities: const platform.Capabilities(
              platformKind: platform.PlatformKind.fake,
              canBond: true,
              canRequestPhy: true,
              canRequestConnectionParameters: true,
            ),
          ),
        );

        // assert
        expect(fake.asked, isEmpty);
        expect((connection.android, connection.ios), (null, null));
      });
    });

    group('the order of refusals', () {
      test('a platform that cannot ask for an MTU says so, however large the '
          'MTU asked for', () async {
        // arrange
        await connectOn(
          AskedFake(
            capabilities: const platform.Capabilities(
              platformKind: platform.PlatformKind.android,
              maxMtu: 247,
            ),
          ),
        );

        // act
        final asking = connection.android!.requestMtu(Mtu(517));

        // assert
        await expectLater(
          asking,
          throwsA(
            isA<UnsupportedOperationException>().having(
              (e) => e.operation,
              'operation',
              'requestMtu',
            ),
          ),
        );
      });
    });

    group('bond state reports', () {
      test(
        'a platform bond stream error never reaches bondStateChanges',
        () async {
          // arrange
          await connectOn(AskedFake(capabilities: android));
          final seen = <BondState>[];
          final errors = <Object>[];
          connection.android!.bondStateChanges.listen(
            seen.add,
            onError: errors.add,
          );

          // act
          fake.simulateBondStateError(deviceId, StateError('boom'));
          fake.simulateBondState(deviceId, platform.PlatformBondState.bonded);
          await pumpEventQueue();

          // assert
          expect(seen, [BondState.none, BondState.bonded]);
          expect(errors, isEmpty);
        },
      );
    });
  });
}

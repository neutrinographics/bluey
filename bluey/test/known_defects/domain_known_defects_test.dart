/// Known defects from the audit of 2026-11-17
/// (docs/reviews/2026-11-17-correctness-and-test-rig-audit.md).
///
/// Each test asserts what an app would reasonably expect and fails today.
/// The slice that fixes a defect moves its test into the suite of the code
/// it fixes and takes it out of this file.
@Tags(['known-defect'])
library;
import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

final class _ControlServiceRejectingPlatform extends FakeBlueyPlatform {
  int failuresLeft = 1;

  @override
  Future<platform.PlatformLocalService> addService(
    platform.PlatformLocalService service,
  ) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const platform.GattOperationUnknownPlatformException(
        'addService',
        code: 'bluey-unknown',
        message: 'transient native failure',
      );
    }
    return super.addService(service);
  }
}

void main() {
  const address = 'AA:BB:CC:DD:EE:01';
  const centralId = 'CC:CC:CC:CC:CC:01';
  late FakeBlueyPlatform fake;
  late Bluey bluey;

  Device device(String a) => Device(address: DeviceAddress(a));

  setUp(() async {
    fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
    bluey = await Bluey.create(localIdentity: TestServerIds.localIdentity);
  });

  group('H3 (I381): remote disconnect never finalises the Connection', () {
    test('stateChanges closes after the peer drops the link', () async {
      fake.simulatePeripheral(id: address);
      final connection = await bluey.connect(device(address));
      var done = false;
      connection.stateChanges.listen((_) {}, onDone: () => done = true);

      fake.simulateDisconnection(address);
      await pumpEventQueue();

      expect(connection.state, ConnectionState.disconnected);
      expect(
        done,
        isTrue,
        reason: 'await-for consumers of stateChanges hang forever',
      );
    });

    test('disconnect() after a remote drop still releases resources', () async {
      fake.simulatePeripheral(id: address);
      final connection = await bluey.connect(device(address));
      var done = false;
      connection.stateChanges.listen((_) {}, onDone: () => done = true);

      fake.simulateDisconnection(address);
      await pumpEventQueue();
      await connection.disconnect();
      await pumpEventQueue();

      expect(
        done,
        isTrue,
        reason: 'disconnect() early-returns, so cleanup can never run',
      );
    });
  });

  group('H2 (I380): peer discovery probes tear down live connections', () {
    test('discoverPeers leaves an existing peer connection intact', () async {
      fake.simulateBlueyServer(
        address: address,
        serverId: TestServerIds.remoteIdentity,
      );
      final peer = await bluey.connectAsPeer(device(address));
      expect(fake.connectedDeviceIds, contains(address));

      await bluey.discoverPeers(timeout: const Duration(milliseconds: 300));
      await pumpEventQueue();

      expect(
        fake.connectedDeviceIds,
        contains(address),
        reason: 'the probe disconnected the link the app was using',
      );
      expect(peer.connection.state, isNot(ConnectionState.disconnected));
    });
  });

  group('M4 (I336): scan restart without awaiting cancel', () {
    test('second scan delivers results', () async {
      fake.simulatePeripheral(id: address, name: 'x');
      final scanner = bluey.scanner();

      final first = scanner.scan().listen((_) {});
      await pumpEventQueue();
      unawaited(first.cancel());

      final results = <ScanResult>[];
      final second = scanner.scan().listen(results.add);
      await pumpEventQueue();

      expect(results, isNotEmpty, reason: 'restarted scan is silently dead');
      expect(scanner.isScanning, isTrue);
      await second.cancel();
      scanner.dispose();
    });

    test('platform scan is not left running while scanner says stopped',
        () async {
      fake.simulatePeripheral(id: address, name: 'x');
      final scanner = bluey.scanner();

      final first = scanner.scan().listen((_) {});
      await pumpEventQueue();
      unawaited(first.cancel());
      scanner.scan().listen((_) {});
      await pumpEventQueue();

      expect(
        fake.isScanning,
        scanner.isScanning,
        reason: 'radio keeps scanning but the domain reports stopped',
      );
    });
  });

  group('M5 (I382): dispose while scanning', () {
    test('dispose stops the platform scan', () async {
      final scanner = bluey.scanner();
      scanner.scan().listen((_) {});
      await pumpEventQueue();
      expect(fake.isScanning, isTrue);

      scanner.dispose();
      await pumpEventQueue();

      expect(fake.isScanning, isFalse, reason: 'native scan leaks on dispose');
    });
  });

  group('L1 (I386): advertising state desync', () {
    test('a rejected re-start does not make stopAdvertising a no-op',
        () async {
      final server = bluey.server()!;
      await server.startAdvertising(name: 'a');
      expect(fake.isAdvertising, isTrue);

      fake.advertisingShouldFail = true;
      await expectLater(server.startAdvertising(name: 'b'), throwsA(anything));

      await server.stopAdvertising();
      expect(
        fake.isAdvertising,
        isFalse,
        reason: 'radio still advertising and can no longer be stopped',
      );
    });
  });

  group('M7 (I384): server request with no handler attached', () {
    test('a read with no readRequests listener is answered', () async {
      final server = bluey.server()!;
      await server.addService(
        HostedService(
          uuid: UUID(TestUuids.customService),
          characteristics: [
            HostedCharacteristic.readable(uuid: UUID(TestUuids.customChar1)),
          ],
        ),
      );
      fake.simulateCentralConnection(centralId: centralId);
      await pumpEventQueue();

      final settled = fake
          .simulateReadRequest(
            centralId: centralId,
            characteristicUuid: TestUuids.customChar1,
          )
          .then<Object?>((v) => v, onError: (Object e) => e);

      await expectLater(
        settled.timeout(const Duration(seconds: 1)),
        completes,
        reason: 'request is dropped; the central waits out the ATT timeout',
      );
    });
  });

  group('M6 (I383): control-service registration failure', () {
    test('a transient addService failure does not brick the server', () async {
      final unhandled = <Object>[];
      final outcome = Completer<List<Object?>>();
      runZonedGuarded(() async {
        final failing = _ControlServiceRejectingPlatform();
        platform.BlueyPlatform.instance = failing;
        final b = await Bluey.create(
          localIdentity: TestServerIds.localIdentity,
        );
        final server = b.server()!;
        await pumpEventQueue();

        final errors = <Object?>[];
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            await server.addService(
              HostedService(
                uuid: UUID(TestUuids.customService),
                characteristics: [
                  HostedCharacteristic.readable(
                    uuid: UUID(TestUuids.customChar1),
                  ),
                ],
              ),
            );
            errors.add(null);
          } catch (e) {
            errors.add(e);
          }
        }
        outcome.complete(errors);
      }, (e, _) => unhandled.add(e));

      final errors = await outcome.future;
      await pumpEventQueue();
      // ignore: avoid_print
      print('unhandled=$unhandled addService errors=$errors');
      expect(unhandled, isEmpty, reason: 'unhandled async error at server()');
      expect(
        errors.last,
        anyOf(isNull, isA<BlueyException>()),
        reason: 'server is permanently unusable: every later call rethrows '
            'the cached, untranslated platform error',
      );
    });
  });
}

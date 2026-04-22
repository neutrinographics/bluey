import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart' as lifecycle;
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Verifies that successful GATT ops on the connection record
/// activity on the lifecycle client. Task 4 covers connection-level
/// methods (services, requestMtu, readRssi); Task 5 adds tests for
/// remote characteristic / descriptor ops via direct construction.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection activity — own methods', () {
    test('requestMtu success causes the next heartbeat tick to skip', () {
      fakeAsync((async) {
        fakePlatform.simulateBlueyServer(
          address: TestDeviceIds.device1,
          serverId: ServerId.generate(),
        );

        final bluey = Bluey();
        late Connection conn;
        bluey
            .connect(Device(
              id: UUID('00000000-0000-0000-0000-aabbccddee01'),
              address: TestDeviceIds.device1,
              name: 'Test Device',
            ))
            .then((c) => conn = c);
        async.flushMicrotasks();

        // Let the initial heartbeat + interval read settle so the
        // periodic timer is up with a known activity baseline.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        // Baseline: clear prior heartbeats.
        fakePlatform.writeCharacteristicCalls.clear();

        // requestMtu — records activity on success.
        conn.requestMtu(247);
        async.flushMicrotasks();

        // Advance through one full tick interval (5s default).
        // With activity recorded just now, the tick's shouldSendProbe
        // should return false.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        final heartbeatWrites = fakePlatform.writeCharacteristicCalls.where(
          (c) => c.characteristicUuid == lifecycle.heartbeatCharUuid,
        );
        expect(heartbeatWrites, isEmpty,
            reason: 'tick within activity window should skip');

        conn.disconnect();
        bluey.dispose();
        async.flushMicrotasks();
      });
    });
  });
}

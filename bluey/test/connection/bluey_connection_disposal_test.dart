import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// I003 — per-characteristic notification controllers leaked across
/// connect/disconnect cycles because `BlueyConnection._cleanup()`
/// closed only the connection-level controllers (state / bond / PHY)
/// and never walked the cached service tree to close the lazily-built
/// per-characteristic notification controllers. Over many cycles
/// memory grew monotonically.
///
/// Fix: `BlueyRemoteCharacteristic` and `BlueyRemoteService` get
/// `dispose()` methods; `BlueyConnection._cleanup()` calls
/// `service.dispose()` on every cached service before nulling
/// `_cachedServices`.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  group('BlueyConnection notification-controller disposal (I003)', () {
    test(
        'subscribed notification stream emits done when the connection '
        'is disconnected — proves the per-characteristic controller is '
        'closed by _cleanup()', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Heart Rate Monitor',
        services: [
          const platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                properties: platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ],
      );

      final bluey = Bluey();
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Heart Rate Monitor',
      );
      final connection = await bluey.connect(device);
      final services = await connection.services();
      final characteristic = services.first.characteristics().first;

      // Subscribe — this lazily creates the notification controller
      // inside BlueyRemoteCharacteristic. With the leak in place the
      // controller is never closed; with the fix in place it must be
      // closed when the connection is disconnected.
      final doneCompleter = Completer<void>();
      final sub = characteristic.notifications.listen(
        (_) {},
        onDone: doneCompleter.complete,
      );

      await connection.disconnect();

      // The done event must fire within a reasonable window if the
      // controller was closed by _cleanup(). Give it 1 second — it
      // should be effectively immediate (next microtask).
      await doneCompleter.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail(
          'notification stream did not emit done after disconnect — '
          'BlueyRemoteCharacteristic._notificationController must be '
          'closed by BlueyConnection._cleanup() (I003)',
        ),
      );

      await sub.cancel();
      bluey.dispose();
    });

    test(
        'subscribing across multiple characteristics on the same connection '
        'closes every controller on disconnect', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Multi-Char Sensor',
        services: [
          const platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                properties: platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
              platform.PlatformCharacteristic(
                uuid: '00002a38-0000-1000-8000-00805f9b34fb',
                properties: platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ],
      );

      final bluey = Bluey();
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Multi-Char Sensor',
      );
      final connection = await bluey.connect(device);
      final services = await connection.services();
      final chars = services.first.characteristics();

      final doneCompleters = chars.map((_) => Completer<void>()).toList();
      final subs = <StreamSubscription<Uint8List>>[];
      for (var i = 0; i < chars.length; i++) {
        subs.add(chars[i].notifications.listen(
              (_) {},
              onDone: doneCompleters[i].complete,
            ));
      }

      await connection.disconnect();

      // Every per-characteristic controller must be closed.
      await Future.wait([
        for (final c in doneCompleters)
          c.future.timeout(
            const Duration(seconds: 1),
            onTimeout: () => fail(
              'at least one notification stream did not emit done after '
              'disconnect — BlueyRemoteService.dispose() must iterate '
              'all characteristics (I003)',
            ),
          ),
      ]);

      for (final s in subs) {
        await s.cancel();
      }
      bluey.dispose();
    });

    test(
        'characteristics that were never subscribed do not break disposal '
        '(idempotent dispose() on a never-listened controller)', () async {
      // Regression guard: BlueyRemoteCharacteristic.dispose() must be
      // safe to call when the controller was never created (the
      // characteristic exists in the service tree but no consumer ever
      // accessed `notifications`).
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Unread Sensor',
        services: [
          const platform.PlatformService(
            uuid: '0000180d-0000-1000-8000-00805f9b34fb',
            isPrimary: true,
            characteristics: [
              platform.PlatformCharacteristic(
                uuid: '00002a37-0000-1000-8000-00805f9b34fb',
                properties: platform.PlatformCharacteristicProperties(
                  canRead: false,
                  canWrite: false,
                  canWriteWithoutResponse: false,
                  canNotify: true,
                  canIndicate: false,
                ),
                descriptors: [],
                handle: 0,
              ),
            ],
            includedServices: [],
          ),
        ],
      );

      final bluey = Bluey();
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
        address: TestDeviceIds.device1,
        name: 'Unread Sensor',
      );
      final connection = await bluey.connect(device);
      await connection.services();

      // No subscribe; just disconnect. Must not throw.
      await connection.disconnect();

      bluey.dispose();
    });
  });
}

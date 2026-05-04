import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Surface-area tests for D.11 (I088): Service Changed must invalidate
/// in-flight GATT ops and the cached service tree, and the next
/// `services()` call must mint a fresh handle table.
///
/// The native sides (Android `onServiceChanged`, iOS
/// `peripheral(_, didModifyServices:)`) clear their handle tables before
/// re-discovery (D.3, D.5). This test pins down the Dart-side surface:
/// pending ops fail with a typed `AttributeHandleInvalidatedException`,
/// the service cache is dropped, and re-discovery returns new handles.
void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  const _serviceUuid = TestUuids.customService;
  const _charUuid = TestUuids.customChar1;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;

    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Service Changed Test Device',
      services: [
        TestServiceBuilder(_serviceUuid).withReadable(_charUuid).build(),
      ],
    );

    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  Device buildDevice() => Device(
    id: UUID('00000000-0000-0000-0000-aabbccddee01'),
    address: TestDeviceIds.device1,
    name: 'Service Changed Test Device',
  );

  group('Service Changed handle invalidation', () {
    test('pending GATT op fails with AttributeHandleInvalidatedException '
        'when Service Changed fires', () async {
      final conn = await bluey.connect(buildDevice());
      final services = await conn.services();
      final char = services.first.characteristic(UUID(_charUuid));

      // Hold the next read indefinitely so we can fire Service Changed
      // while the read is still pending.
      fakePlatform.holdNextReadCharacteristic();

      final readFuture = char.read();

      // Service Changed mid-read.
      fakePlatform.simulateServiceChange(TestDeviceIds.device1);

      // The pending future must surface the typed exception, not the
      // platform's lower-level signal.
      await expectLater(
        readFuture,
        throwsA(isA<AttributeHandleInvalidatedException>()),
      );

      await conn.disconnect();
    });

    test('cached services are invalidated by Service Changed; '
        'next services() triggers re-discovery', () async {
      final conn = await bluey.connect(buildDevice());
      await conn.services(cache: true);
      expect(
        fakePlatform.discoverServicesCalls,
        equals([TestDeviceIds.device1]),
      );

      fakePlatform.simulateServiceChange(TestDeviceIds.device1);
      // Let the broadcast stream deliver the event so the cache
      // clear lands before the next services() call.
      await pumpEventQueue();

      // Even with cache: true, the next call must re-discover because
      // the cache was cleared.
      await conn.services(cache: true);
      expect(
        fakePlatform.discoverServicesCalls,
        equals([TestDeviceIds.device1, TestDeviceIds.device1]),
      );

      await conn.disconnect();
    });

    test('servicesChanges emits the freshly-discovered service list after '
        'Service Changed', () async {
      final conn = await bluey.connect(buildDevice());
      await conn.services();

      // Capture every emission on the new stream.
      final emissions = <List<RemoteService>>[];
      final sub = conn.servicesChanges.listen(emissions.add);
      addTearDown(sub.cancel);

      // No emission yet — the stream fires on Service-Changed-driven
      // re-discovery, not on initial discovery.
      expect(emissions, isEmpty);

      fakePlatform.simulateServiceChange(TestDeviceIds.device1);
      // Let the platform's serviceChanges stream deliver to the
      // BlueyConnection listener AND let the re-discovery complete.
      await pumpEventQueue();

      expect(
        emissions,
        hasLength(1),
        reason: 'one emission expected after Service Changed re-discovery',
      );
      expect(
        emissions.single,
        isNotEmpty,
        reason: 'emission carries the freshly-discovered service list',
      );
      expect(
        emissions.single.map((s) => s.uuid.toString()).toList(),
        contains(_serviceUuid),
      );

      await conn.disconnect();
    });

    test(
      'servicesChanges is a broadcast stream supporting multiple listeners',
      () async {
        final conn = await bluey.connect(buildDevice());
        await conn.services();

        final a = <List<RemoteService>>[];
        final b = <List<RemoteService>>[];
        final subA = conn.servicesChanges.listen(a.add);
        final subB = conn.servicesChanges.listen(b.add);
        addTearDown(() async {
          await subA.cancel();
          await subB.cancel();
        });

        fakePlatform.simulateServiceChange(TestDeviceIds.device1);
        await pumpEventQueue();

        expect(a, hasLength(1));
        expect(b, hasLength(1));

        await conn.disconnect();
      },
    );

    test('new handles work for reads after re-discovery', () async {
      final conn = await bluey.connect(buildDevice());
      await conn.services();

      fakePlatform.simulateServiceChange(TestDeviceIds.device1);
      await pumpEventQueue();

      // Mutate the underlying value so we can verify the post-Service-
      // Changed read uses the fresh handle table to retrieve it.
      final freshServices = await conn.services();
      final freshChar = freshServices.first.characteristic(UUID(_charUuid));
      fakePlatform.setCharacteristicValueByHandle(
        TestDeviceIds.device1,
        freshChar.handle.value,
        Uint8List.fromList([0x42]),
      );

      final value = await freshChar.read();
      expect(value, equals(Uint8List.fromList([0x42])));

      await conn.disconnect();
    });
  });
}

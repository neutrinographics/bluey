import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Tests for D.10 of the handle-identity rewrite (I088): the singular
/// navigation accessors throw `AmbiguousAttributeException` when two
/// or more attributes share the requested UUID, and a plural accessor
/// returns the full match list (filtered by UUID if asked, all if not).
///
/// Background: prior to D.10, `service.characteristic(uuid)` silently
/// returned the first match on a duplicate-UUID peripheral. That meant
/// ops on the wrong attribute on devices that legitimately host
/// multiple chars or services with the same UUID. After D.10, the
/// ambiguity is loud — the caller is forced to disambiguate via the
/// new `characteristics({UUID? uuid})` plural accessor and pick by
/// handle.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  const serviceA = '0000aaaa-0000-1000-8000-00805f9b34fb';
  const serviceB = '0000bbbb-0000-1000-8000-00805f9b34fb';
  const sharedServiceUuid = '0000dddd-0000-1000-8000-00805f9b34fb';
  const charUniqueUuid = '0000cc01-0000-1000-8000-00805f9b34fb';
  const charDupUuid = '0000cccc-0000-1000-8000-00805f9b34fb';
  const descDupUuid = '00002901-0000-1000-8000-00805f9b34fb';
  const descUniqueUuid = '00002904-0000-1000-8000-00805f9b34fb';

  Future<RemoteService> connectAndGetServiceWith({
    required List<platform.PlatformCharacteristic> characteristics,
    String serviceUuid = serviceA,
  }) async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Test Peripheral',
      services: [
        platform.PlatformService(
          uuid: serviceUuid,
          isPrimary: true,
          characteristics: characteristics,
          includedServices: const [],
        ),
      ],
    );
    final bluey = Bluey();
    final device = await scanFirstDevice(bluey);
    final connection = await bluey.connect(device);
    final services = await connection.services();
    return services.single;
  }

  group('RemoteService.characteristic(uuid)', () {
    test(
      'throws AmbiguousAttributeException when two chars share UUID',
      () async {
        final service = await connectAndGetServiceWith(
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charDupUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
              handle: 0,
            ),
            platform.PlatformCharacteristic(
              uuid: charDupUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
              handle: 0,
            ),
          ],
        );

        expect(
          () => service.characteristic(UUID(charDupUuid)),
          throwsA(
            isA<AmbiguousAttributeException>()
                .having((e) => e.uuid, 'uuid', equals(UUID(charDupUuid)))
                .having((e) => e.matchCount, 'matchCount', equals(2)),
          ),
        );
      },
    );

    test('throws CharacteristicNotFoundException when no match', () async {
      final service = await connectAndGetServiceWith(
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: charUniqueUuid,
            properties: TestProperties.readOnly,
            descriptors: [],
            handle: 0,
          ),
        ],
      );

      expect(
        () => service.characteristic(UUID(charDupUuid)),
        throwsA(isA<CharacteristicNotFoundException>()),
      );
    });

    test('returns the single match when exactly one char matches', () async {
      final service = await connectAndGetServiceWith(
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: charUniqueUuid,
            properties: TestProperties.readOnly,
            descriptors: [],
            handle: 0,
          ),
        ],
      );

      final char = service.characteristic(UUID(charUniqueUuid));
      expect(char.uuid, equals(UUID(charUniqueUuid)));
    });
  });

  group('RemoteService.characteristics({uuid})', () {
    test(
      'returns all duplicate-UUID matches when filter is supplied',
      () async {
        final service = await connectAndGetServiceWith(
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charDupUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
              handle: 0,
            ),
            platform.PlatformCharacteristic(
              uuid: charDupUuid,
              properties: TestProperties.readWrite,
              descriptors: [],
              handle: 0,
            ),
            platform.PlatformCharacteristic(
              uuid: charUniqueUuid,
              properties: TestProperties.readOnly,
              descriptors: [],
              handle: 0,
            ),
          ],
        );

        final dupes = service.characteristics(uuid: UUID(charDupUuid));
        expect(dupes, hasLength(2));
        expect(dupes.every((c) => c.uuid == UUID(charDupUuid)), isTrue);
        // The handles must be distinct — that's the whole point of the
        // disambiguation.
        expect(dupes[0].handle, isNot(equals(dupes[1].handle)));
      },
    );

    test('returns all characteristics when no filter is supplied', () async {
      final service = await connectAndGetServiceWith(
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: charDupUuid,
            properties: TestProperties.readWrite,
            descriptors: [],
            handle: 0,
          ),
          platform.PlatformCharacteristic(
            uuid: charDupUuid,
            properties: TestProperties.readWrite,
            descriptors: [],
            handle: 0,
          ),
          platform.PlatformCharacteristic(
            uuid: charUniqueUuid,
            properties: TestProperties.readOnly,
            descriptors: [],
            handle: 0,
          ),
        ],
      );

      final all = service.characteristics();
      expect(all, hasLength(3));
    });
  });

  group('Connection.service(uuid)', () {
    test(
      'throws AmbiguousAttributeException when two services share UUID',
      () async {
        fakePlatform.simulatePeripheral(
          id: TestDeviceIds.device1,
          name: 'Two-Service Peripheral',
          services: const [
            platform.PlatformService(
              uuid: sharedServiceUuid,
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
            platform.PlatformService(
              uuid: sharedServiceUuid,
              isPrimary: true,
              characteristics: [],
              includedServices: [],
            ),
          ],
        );
        final bluey = Bluey();
        final device = await scanFirstDevice(bluey);
        final connection = await bluey.connect(device);
        // Trigger discovery so the cache is populated.
        await connection.services();

        expect(
          () => connection.service(UUID(sharedServiceUuid)),
          throwsA(
            isA<AmbiguousAttributeException>()
                .having((e) => e.uuid, 'uuid', equals(UUID(sharedServiceUuid)))
                .having((e) => e.matchCount, 'matchCount', equals(2)),
          ),
        );
      },
    );

    test('returns the single match when exactly one service matches', () async {
      fakePlatform.simulatePeripheral(
        id: TestDeviceIds.device1,
        name: 'Single-Service Peripheral',
        services: const [
          platform.PlatformService(
            uuid: serviceA,
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
          platform.PlatformService(
            uuid: serviceB,
            isPrimary: true,
            characteristics: [],
            includedServices: [],
          ),
        ],
      );
      final bluey = Bluey();
      final device = await scanFirstDevice(bluey);
      final connection = await bluey.connect(device);
      await connection.services();

      final svc = connection.service(UUID(serviceA));
      expect(svc.uuid, equals(UUID(serviceA)));
    });
  });

  group('RemoteCharacteristic.descriptor(uuid)', () {
    test(
      'throws AmbiguousAttributeException when two descriptors share UUID',
      () async {
        final service = await connectAndGetServiceWith(
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charUniqueUuid,
              properties: TestProperties.readOnly,
              descriptors: [
                platform.PlatformDescriptor(uuid: descDupUuid, handle: 0),
                platform.PlatformDescriptor(uuid: descDupUuid, handle: 0),
              ],
              handle: 0,
            ),
          ],
        );
        final char = service.characteristic(UUID(charUniqueUuid));

        expect(
          () => char.descriptor(UUID(descDupUuid)),
          throwsA(
            isA<AmbiguousAttributeException>()
                .having((e) => e.uuid, 'uuid', equals(UUID(descDupUuid)))
                .having((e) => e.matchCount, 'matchCount', equals(2)),
          ),
        );
      },
    );

    test(
      'returns the single match when exactly one descriptor matches',
      () async {
        final service = await connectAndGetServiceWith(
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charUniqueUuid,
              properties: TestProperties.readOnly,
              descriptors: [
                platform.PlatformDescriptor(uuid: descUniqueUuid, handle: 0),
              ],
              handle: 0,
            ),
          ],
        );
        final char = service.characteristic(UUID(charUniqueUuid));
        final desc = char.descriptor(UUID(descUniqueUuid));
        expect(desc.uuid, equals(UUID(descUniqueUuid)));
      },
    );
  });

  group('RemoteCharacteristic.descriptors({uuid})', () {
    test(
      'returns all duplicate-UUID descriptors when filter is supplied',
      () async {
        final service = await connectAndGetServiceWith(
          characteristics: const [
            platform.PlatformCharacteristic(
              uuid: charUniqueUuid,
              properties: TestProperties.readOnly,
              descriptors: [
                platform.PlatformDescriptor(uuid: descDupUuid, handle: 0),
                platform.PlatformDescriptor(uuid: descDupUuid, handle: 0),
                platform.PlatformDescriptor(uuid: descUniqueUuid, handle: 0),
              ],
              handle: 0,
            ),
          ],
        );
        final char = service.characteristic(UUID(charUniqueUuid));

        final dupes = char.descriptors(uuid: UUID(descDupUuid));
        expect(dupes, hasLength(2));
        expect(dupes.every((d) => d.uuid == UUID(descDupUuid)), isTrue);
        expect(dupes[0].handle, isNot(equals(dupes[1].handle)));
      },
    );

    test('returns all descriptors when no filter is supplied', () async {
      final service = await connectAndGetServiceWith(
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: charUniqueUuid,
            properties: TestProperties.readOnly,
            descriptors: [
              platform.PlatformDescriptor(uuid: descDupUuid, handle: 0),
              platform.PlatformDescriptor(uuid: descUniqueUuid, handle: 0),
            ],
            handle: 0,
          ),
        ],
      );
      final char = service.characteristic(UUID(charUniqueUuid));

      expect(char.descriptors(), hasLength(2));
    });
  });

  test(
    'AmbiguousAttributeException message points at plural accessor',
    () async {
      final service = await connectAndGetServiceWith(
        characteristics: const [
          platform.PlatformCharacteristic(
            uuid: charDupUuid,
            properties: TestProperties.readWrite,
            descriptors: [],
            handle: 0,
          ),
          platform.PlatformCharacteristic(
            uuid: charDupUuid,
            properties: TestProperties.readWrite,
            descriptors: [],
            handle: 0,
          ),
        ],
      );

      try {
        service.characteristic(UUID(charDupUuid));
        fail('expected AmbiguousAttributeException');
      } on AmbiguousAttributeException catch (e) {
        expect(e.toString(), contains('characteristics(uuid:'));
      }
    },
  );
}

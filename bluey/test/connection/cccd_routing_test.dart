import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

/// Load-bearing tests for I011: enabling notifications on one
/// characteristic must only toggle that characteristic's CCCD, even
/// when a sibling characteristic on the same service shares the same
/// `notifiable` shape.
///
/// Without per-descriptor-handle CCCD storage, a `setNotification(true)`
/// on charA would write to a UUID-keyed CCCD slot shared with charB,
/// causing charB to look subscribed (or unsubscribed) when only charA's
/// state was meant to change. The handle-identity rewrite gives every
/// CCCD instance its own backing slot keyed by the descriptor's minted
/// handle, so each char's subscription state is isolated.
void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  // One service with two notify-able characteristics, each carrying its
  // own CCCD descriptor (0x2902). Distinct char UUIDs here — the I011
  // shape is about per-CCCD isolation, not duplicate UUIDs.
  const serviceUuid = '0000aaaa-0000-1000-8000-00805f9b34fb';
  const charAUuid = '0000aaa1-0000-1000-8000-00805f9b34fb';
  const charBUuid = '0000aaa2-0000-1000-8000-00805f9b34fb';
  const cccdUuid = '00002902-0000-1000-8000-00805f9b34fb';

  // 16-bit little-endian CCCD bit fields.
  Uint8List notifyEnabled() => Uint8List.fromList([0x01, 0x00]);
  Uint8List notifyDisabled() => Uint8List.fromList([0x00, 0x00]);

  Future<
    ({
      Connection connection,
      RemoteCharacteristic charA,
      RemoteCharacteristic charB,
    })
  >
  connectWithTwoNotifyChars() async {
    fakePlatform.simulatePeripheral(
      id: TestDeviceIds.device1,
      name: 'Two-Notify Peripheral',
      services: const [
        platform.PlatformService(
          uuid: serviceUuid,
          isPrimary: true,
          characteristics: [
            platform.PlatformCharacteristic(
              uuid: charAUuid,
              properties: TestProperties.notifyOnly,
              descriptors: [
                platform.PlatformDescriptor(uuid: cccdUuid, handle: 0),
              ],
              handle: 0,
            ),
            platform.PlatformCharacteristic(
              uuid: charBUuid,
              properties: TestProperties.notifyOnly,
              descriptors: [
                platform.PlatformDescriptor(uuid: cccdUuid, handle: 0),
              ],
              handle: 0,
            ),
          ],
          includedServices: [],
        ),
      ],
    );

    final bluey = Bluey();
    final device = await scanFirstDevice(bluey);
    final connection = await bluey.connect(device);
    final services = await connection.services();
    final chars = services.single.characteristics();
    return (connection: connection, charA: chars[0], charB: chars[1]);
  }

  // Looks up the CCCD handle for [char] and returns its current bytes,
  // or null if no CCCD is mapped (which would indicate the fake didn't
  // discover the descriptor properly — a test bug, not a domain bug).
  Uint8List? cccdFor(RemoteCharacteristic char) {
    final descs = char.descriptors();
    final cccd = descs.firstWhere(
      (d) => d.uuid.toString().toLowerCase() == cccdUuid,
    );
    return fakePlatform.cccdValueByHandle(
      TestDeviceIds.device1,
      cccd.handle.value,
    );
  }

  test('enabling notifications on charA does not toggle charB CCCD', () async {
    final (:connection, :charA, :charB) = await connectWithTwoNotifyChars();

    // Subscribing triggers `setNotification(true, characteristicHandle: ...)`
    // on the platform via `BlueyRemoteCharacteristic._onFirstListen`.
    final sub = charA.notifications.listen((_) {});
    // Pump the event loop so the fire-and-forget setNotification call
    // resolves before we assert on CCCD state.
    await Future<void>.delayed(Duration.zero);

    expect(
      cccdFor(charA),
      equals(notifyEnabled()),
      reason: "charA's CCCD should be enabled (0x0001 LE)",
    );
    expect(
      cccdFor(charB),
      equals(notifyDisabled()),
      reason:
          "charB's CCCD must remain at the default disabled (0x0000) "
          'state — its slot is keyed by a different descriptor handle',
    );

    await sub.cancel();
  });

  test('disabling notifications on charA does not affect charB CCCD', () async {
    final (:connection, :charA, :charB) = await connectWithTwoNotifyChars();

    // Subscribe to BOTH chars first, so each CCCD is enabled.
    final subA = charA.notifications.listen((_) {});
    final subB = charB.notifications.listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(cccdFor(charA), equals(notifyEnabled()));
    expect(cccdFor(charB), equals(notifyEnabled()));

    // Cancelling charA's subscription triggers the
    // `_onLastCancel` path -> setNotification(false).
    await subA.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(
      cccdFor(charA),
      equals(notifyDisabled()),
      reason:
          "charA's CCCD should be cleared after the last subscriber "
          'cancelled',
    );
    expect(
      cccdFor(charB),
      equals(notifyEnabled()),
      reason:
          "charB's CCCD must remain enabled — its CCCD is a distinct "
          'attribute with its own handle',
    );

    await subB.cancel();
  });
}

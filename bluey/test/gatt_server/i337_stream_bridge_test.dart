import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

/// I337 regression: the identifier on a connected [Client] must EQUAL the
/// value emitted on [Server.disconnections] for the same client.
///
/// Previously, [BlueyClient.id] returned a lossy UUID synthesised from the
/// raw MAC address bytes (via `codeUnits` + `padLeft(32,...)`), while
/// [Server.disconnections] emitted the verbatim raw MAC. Because the two
/// values were different types (UUID vs String), consumer code that bridged
/// `peerConnections` and `disconnections` could never match them.
///
/// After this refactor:
/// - [Client.address] is a [ClientAddress] value object wrapping the verbatim
///   platform string.
/// - [Server.disconnections] is a `Stream<ClientAddress>` emitting the same
///   value object.
/// - The two values are equal by value ([ClientAddress.==]).
void main() {
  late FakeBlueyPlatform fake;

  setUp(() {
    fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
  });

  group('I337: Client.address == disconnections value', () {
    test(
        'Client.address equals the value emitted on disconnections '
        '(Android MAC)', () async {
      final bluey = await Bluey.create();
      final server = bluey.server()!;

      // The verbatim 17-char MAC from the I337 bug report.
      const mac = '46:F9:31:94:D7:F6';

      await server.startAdvertising();

      final connected = <ClientAddress>[];
      final gone = <ClientAddress>[];
      server.connections.listen((c) => connected.add(c.address));
      server.disconnections.listen(gone.add);

      fake.simulateCentralConnection(centralId: mac);
      await Future<void>.delayed(Duration.zero);
      fake.simulateCentralDisconnection(mac);
      await Future<void>.delayed(Duration.zero);

      expect(
        connected.single,
        const ClientAddress(mac),
        reason: 'Client.address must be the verbatim platform string',
      );
      expect(
        gone.single,
        const ClientAddress(mac),
        reason: 'disconnections must emit the verbatim platform string',
      );
      // This is the core I337 invariant: the bridge key must be identical
      // across both streams. A PeerClient from peerConnections just wraps the
      // same Client, so peer.client.address is the identical value — see the
      // note in the spec.
      expect(
        connected.single,
        gone.single,
        reason:
            'the bridge key must be identical across both streams (I337)',
      );

      await bluey.dispose();
    });

    test(
        'Client.address equals the value emitted on disconnections '
        '(iOS CBPeer UUID string)', () async {
      final bluey = await Bluey.create();
      final server = bluey.server()!;

      // An iOS CBCentral.identifier UUID string (uppercase, hyphenated).
      const iosId = '6BA7B810-9DAD-11D1-80B4-00C04FD430C8';

      await server.startAdvertising();

      final connected = <ClientAddress>[];
      final gone = <ClientAddress>[];
      server.connections.listen((c) => connected.add(c.address));
      server.disconnections.listen(gone.add);

      fake.simulateCentralConnection(centralId: iosId);
      await Future<void>.delayed(Duration.zero);
      fake.simulateCentralDisconnection(iosId);
      await Future<void>.delayed(Duration.zero);

      expect(connected.single, const ClientAddress(iosId));
      expect(gone.single, const ClientAddress(iosId));
      expect(
        connected.single,
        gone.single,
        reason: 'bridge key must be identical for iOS UUIDs too (I337)',
      );

      await bluey.dispose();
    });
  });
}

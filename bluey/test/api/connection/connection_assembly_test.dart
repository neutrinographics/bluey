import 'package:bluey/src/api/connection/connection.dart';
import 'package:bluey/src/api/connection/connection_assembly.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/exceptions.dart';
import 'package:bluey/src/shared/infrastructure/bluey_event_bus.dart';
import 'package:bluey/src/shared/infrastructure/bluey_logger.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fixtures/features/connection/application/ports/in_memory_connection_ports.dart';
import '../../fixtures/features/connection/application/ports/in_memory_links.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  late InMemoryLinks links;
  late ConnectionAssembly assembly;

  setUp(() {
    links = InMemoryLinks()..reach(device);
    final logger = BlueyLogger();
    final platform = FakeBlueyPlatform();
    assembly = ConnectionAssembly(
      ports: inMemoryConnectionPorts(links: links),
      publisher: BlueyEventBus(),
      log: logger,
      now: clock.now,
      platformName: 'fake',
      gattFor:
          (session) => LinkGattClient(
            platformInstance: platform,
            session: session,
            logger: logger,
          ),
    );
  });

  group('connecting', () {
    test('connect presents one Connection per link', () async {
      // arrange
      final first = await assembly.connect(device);

      // act
      final again = await assembly.connect(device);
      await first.disconnect();
      final next = await assembly.connect(device);

      // assert
      expect(identical(again, first), isTrue);
      expect(identical(next, first), isFalse);
    });

    test('connect throws what the failure translates to', () async {
      // arrange
      links.failNextOpen(device, ConnectFailureReason.deviceNotFound);

      // act
      final connecting = assembly.connect(device);

      // assert
      await expectLater(
        connecting,
        throwsA(
          isA<ConnectionException>().having(
            (e) => e.deviceAddress,
            'deviceAddress',
            device,
          ),
        ),
      );
    });
  });

  group('borrowing', () {
    test('a borrow presents the Connection connect returns', () async {
      // arrange
      final borrowed = await assembly.borrow(device);

      // act
      final connection = await assembly.connect(device);

      // assert
      expect(identical(borrowed.connection, connection), isTrue);
    });
  });

  group('the platform', () {
    test('a presented Connection names the platform it was assembled '
        'for', () async {
      // arrange
      final unsupported = _CloseUnsupported()..reach(device);
      final logger = BlueyLogger();
      final platform = FakeBlueyPlatform();
      final named = ConnectionAssembly(
        ports: inMemoryConnectionPorts(links: unsupported),
        publisher: BlueyEventBus(),
        log: logger,
        now: clock.now,
        platformName: 'nameOfThisPlatform',
        gattFor:
            (session) => LinkGattClient(
              platformInstance: platform,
              session: session,
              logger: logger,
            ),
      );
      final connection = await named.connect(device);

      // act
      final disconnecting = connection.disconnect();

      // assert
      await expectLater(
        disconnecting,
        throwsA(
          isA<UnsupportedOperationException>().having(
            (e) => e.platform,
            'platform',
            'nameOfThisPlatform',
          ),
        ),
      );
    });
  });

  group('link ids', () {
    test(
      'answers the link id behind a Connection it presented, and null for any other',
      () async {
        // arrange
        final connection = await assembly.connect(device);

        // act
        final presented = assembly.linkIdOf(connection);
        final foreign = assembly.linkIdOf(_ForeignConnection());

        // assert
        expect(presented, LinkId(device.value));
        expect(foreign, isNull);
      },
    );
  });
}

/// A radio whose links cannot be closed on this platform, so the one
/// failure that names the platform is reachable through a Connection.
final class _CloseUnsupported extends InMemoryLinks {
  @override
  Future<Either<ConnectionFailure, void>> close(LinkId link) async =>
      const Left(FeatureUnsupported(LinkOperation.close));
}

/// A Connection the assembly never presented, as an app's own one would be.
final class _ForeignConnection implements Connection {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

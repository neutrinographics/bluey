import 'package:clock/clock.dart';
import 'package:bluey/src/api/connection/bluey_connection.dart';
import 'package:bluey/src/api/connection/borrowed_connection.dart';
import 'package:bluey/src/api/connection/connection.dart';
import 'package:bluey/src/api/connection/connections.dart';
import 'package:bluey/src/api/connection/connection_failure_translation.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey/src/features/connection/application/borrow_link.dart';
import 'package:bluey/src/features/connection/application/connect_device.dart';
import 'package:bluey/src/features/connection/application/link_registry.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_links.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/infrastructure/bluey_event_bus.dart';
import 'package:bluey/src/shared/infrastructure/bluey_logger.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

/// The wiring Bluey does, over any BlueyPlatform, for tests that need a
/// Connection without a Bluey.
///
/// Every Connection and borrow it hands out shares one registry, so a test
/// sees the same one-owner-per-link rules an app does.
class ConnectionRig {
  ConnectionRig(
    platform.BlueyPlatform platform, {
    BlueyLogger? logger,
    BlueyEventBus? events,
  }) {
    final log = logger ?? BlueyLogger();
    final bus = events ?? BlueyEventBus();
    final registry = LinkRegistry(
      links: PlatformLinks(platform, log: log),
      events: bus,
      log: log,
      now: clock.now,
    );
    _connectDevice = ConnectDevice(registry);
    _connections = Connections(
      present:
          (session) => BlueyConnection(
            session: session,
            gatt: LinkGattClient(
              platformInstance: platform,
              session: session,
              logger: log,
              events: bus,
            ),
          ),
    );
    borrow = borrowingThrough(
      borrowLink: BorrowLink(registry),
      connections: _connections,
    );
  }

  late final ConnectDevice _connectDevice;
  late final Connections _connections;

  /// How a borrower reaches a device's link through this rig's registry.
  late final BorrowConnection borrow;

  /// The app's connect, throwing as Bluey.connect does.
  Future<Connection> connect(DeviceAddress device, {Duration? timeout}) async {
    final answer = await _connectDevice.run(
      ConnectDeviceRequest(device: device, timeout: timeout),
    );
    return _connections.of(valueOrThrow(answer, device: device));
  }

  /// The platform's name for [connection]'s link, as Bluey reads it.
  String connectionIdOf(Connection connection) =>
      _connections.linkIdOf(connection)?.value ??
      connection.deviceAddress.toString();
}

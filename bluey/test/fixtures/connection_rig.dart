import 'package:clock/clock.dart';
import 'package:bluey/src/api/connection/borrowed_connection.dart';
import 'package:bluey/src/api/connection/connection.dart';
import 'package:bluey/src/api/connection/connection_assembly.dart';
import 'package:bluey/src/connection/bluey_connection.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_connection_ports.dart';
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
    _assembly = ConnectionAssembly(
      ports: platformConnectionPorts(platform, log: log),
      publisher: bus,
      log: log,
      now: clock.now,
      platformName: platform.capabilities.platformKind.name,
      gattFor:
          (session) => LinkGattClient(
            platformInstance: platform,
            session: session,
            logger: log,
            events: bus,
          ),
    );
  }

  late final ConnectionAssembly _assembly;

  /// How a borrower reaches a device's link through this rig's registry.
  BorrowConnection get borrow => _assembly.borrow;

  /// The app's connect, throwing as Bluey.connect does.
  Future<Connection> connect(DeviceAddress device, {Duration? timeout}) =>
      _assembly.connect(device, timeout: timeout);

  /// The platform's name for [connection]'s link, as Bluey reads it.
  String connectionIdOf(Connection connection) =>
      _assembly.linkIdOf(connection)?.value ??
      connection.deviceAddress.toString();
}

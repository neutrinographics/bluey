import '../../connection/bluey_connection.dart';
import '../../features/connection/application/borrow_link.dart';
import '../../features/connection/application/connect_device.dart';
import '../../features/connection/application/link_registry.dart';
import '../../features/connection/application/link_session.dart';
import '../../features/connection/application/ports/connection_ports.dart';
import '../../features/connection/domain/link_id.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/application/log.dart';
import '../../shared/application/now.dart';
import '../../shared/domain/device_address.dart';
import 'bluey_connection.dart';
import 'borrowed_connection.dart';
import 'connection.dart';
import 'connection_event_translation.dart';
import 'connection_failure_translation.dart';
import 'connections.dart';

/// Connection as the edge uses it: its units built over its ports, and each
/// link presented as one public Connection.
///
/// Every connect and borrow it answers shares one registry, so the app and a
/// borrower of the same device always hold the same Connection.
final class ConnectionAssembly {
  /// Builds Connection over [ports], announcing its events on [publisher];
  /// [gattFor] builds the GATT operations a session's Connection carries, and
  /// every exception it throws names the platform as [platformName].
  ConnectionAssembly({
    required ConnectionPorts ports,
    required EventPublisher publisher,
    required Log log,
    required Now now,
    required String platformName,
    required LinkGattClient Function(LinkSession session) gattFor,
  }) : _platformName = platformName {
    final registry = LinkRegistry(
      links: ports.links,
      events: PublishedLinkEvents(publisher),
      log: log,
      now: now,
    );
    _connectDevice = ConnectDevice(registry);
    _connections = Connections(
      present:
          (session) => BlueyConnection(
            session: session,
            gatt: gattFor(session),
            platform: platformName,
          ),
    );
    borrow = borrowingThrough(
      borrowLink: BorrowLink(registry),
      connections: _connections,
      platform: platformName,
    );
  }

  final String _platformName;

  late final ConnectDevice _connectDevice;
  late final Connections _connections;

  /// How a borrower reaches a device's link through this assembly's registry.
  late final BorrowConnection borrow;

  /// The app's connect to [device], within [timeout] when one is given.
  ///
  /// Throws the BlueyException Bluey.connect always has.
  Future<Connection> connect(DeviceAddress device, {Duration? timeout}) async {
    final answer = await _connectDevice.run(
      ConnectDeviceRequest(device: device, timeout: timeout),
    );
    return _connections.of(
      valueOrThrow(answer, device: device, platform: _platformName),
    );
  }

  /// The link id behind a Connection this presented; null for any other.
  LinkId? linkIdOf(Connection connection) => _connections.linkIdOf(connection);
}

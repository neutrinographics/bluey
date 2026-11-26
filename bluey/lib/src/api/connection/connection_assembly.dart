import '../../connection/bluey_connection.dart';
import '../../features/connection/application/bonding_session.dart';
import '../../features/connection/application/borrow_link.dart';
import '../../features/connection/application/connect_device.dart';
import '../../features/connection/application/link_registry.dart';
import '../../features/connection/application/link_session.dart';
import '../../features/connection/application/mtu_session.dart';
import '../../features/connection/application/parameter_session.dart';
import '../../features/connection/application/phy_session.dart';
import '../../features/connection/application/ports/connection_ports.dart';
import '../../features/connection/application/read_rssi.dart';
import '../../features/connection/application/read_write_payload_limit.dart';
import '../../features/connection/domain/link_end.dart';
import '../../features/connection/domain/link_id.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/application/log.dart';
import '../../shared/application/now.dart';
import '../../shared/domain/device_address.dart';
import '../../shared/exceptions.dart';
import 'android_connection.dart';
import 'bluey_connection.dart';
import 'borrowed_connection.dart';
import 'connection.dart';
import 'connection_event_translation.dart';
import 'connection_failure_translation.dart';
import 'connections.dart';
import 'ios_connection.dart';

/// Which platform's extension each Connection carries, as the composition
/// root reads it off the platform, so Connection's edge names no other
/// context.
enum ConnectionExtension { android, ios, none }

/// Connection as the edge uses it: its units built over its ports, and each
/// link presented as one public Connection.
///
/// Every connect and borrow it answers shares one registry, so the app and a
/// borrower of the same device always hold the same Connection.
final class ConnectionAssembly {
  /// Builds Connection over [ports], announcing its events on [publisher];
  /// each Connection carries [extension]'s extension and the GATT operations
  /// [gattFor] builds for its session, which throw an ended link as the
  /// exception they are handed. Every exception names the platform as
  /// [platformName].
  ConnectionAssembly({
    required ConnectionPorts ports,
    required EventPublisher publisher,
    required Log log,
    required Now now,
    required ConnectionExtension extension,
    required String platformName,
    required LinkGattClient Function(
      LinkSession session,
      BlueyException Function(LinkEnd end) endAsException,
    )
    gattFor,
  }) : _platformName = platformName {
    final registry = LinkRegistry(
      links: ports.links,
      events: PublishedLinkEvents(publisher),
      log: log,
      now: now,
    );
    final readRssi = ReadRssi(strength: ports.signal, log: log, now: now);
    final readWritePayloadLimit = ReadWritePayloadLimit(
      negotiation: ports.mtu,
      log: log,
      now: now,
    );
    _connectDevice = ConnectDevice(registry);
    _connections = Connections(
      present:
          (session) => BlueyConnection(
            session: session,
            gatt: gattFor(
              session,
              (end) => linkEndAsException(end, device: session.link.device),
            ),
            readRssi: readRssi,
            readWritePayloadLimit: readWritePayloadLimit,
            android:
                extension == ConnectionExtension.android
                    ? _androidOf(session, ports, log, now)
                    : null,
            ios:
                extension == ConnectionExtension.ios
                    ? const IosConnection()
                    : null,
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

  /// The Android extension of [session]'s link, its sessions built at once
  /// so each follows the radio from the link's first moment.
  AndroidConnection _androidOf(
    LinkSession session,
    ConnectionPorts ports,
    Log log,
    Now now,
  ) => AndroidConnection(
    session: session,
    bonding: BondingSession(
      session: session,
      bonding: ports.bonding,
      features: ports.features,
      log: log,
    ),
    phy: PhySession(
      session: session,
      phy: ports.phy,
      features: ports.features,
      log: log,
    ),
    parameters: ParameterSession(
      session: session,
      parameters: ports.parameters,
      features: ports.features,
      log: log,
    ),
    mtu: MtuSession(
      session: session,
      negotiation: ports.mtu,
      features: ports.features,
      log: log,
      now: now,
    ),
    platform: _platformName,
  );
}

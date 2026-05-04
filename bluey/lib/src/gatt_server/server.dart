import 'dart:async';
import 'dart:typed_data';

import '../peer/peer_client.dart';
import '../peer/server_id.dart';
import '../shared/manufacturer_data.dart';
import '../shared/uuid.dart';
import 'gatt_request.dart';
import 'hosted_gatt.dart';

export 'gatt_request.dart';
export 'hosted_gatt.dart';

/// Advertising mode (Android only).
///
/// Controls the advertising interval and power consumption. Honored only on
/// Android — iOS manages advertising intervals automatically and ignores
/// this value.
enum AdvertiseMode {
  /// Lowest power consumption, ~1000 ms advertising interval. Best for
  /// background advertising where quick discovery isn't critical.
  lowPower,

  /// Balanced power consumption, ~250 ms advertising interval.
  balanced,

  /// Lowest latency, ~100 ms advertising interval. Fastest discovery, highest
  /// power consumption.
  lowLatency,
}

/// A connected client device (from the server's perspective).
///
/// When a client connects to this peripheral, a [Client] instance is
/// created to represent it. Use this to send notifications to specific
/// clients.
abstract class Client {
  /// The unique identifier of this client.
  UUID get id;

  /// The current MTU for this connection.
  int get mtu;
}

/// GATT server for peripheral role.
///
/// The Server allows this device to act as a BLE peripheral, advertising
/// services and responding to requests from clients.
///
/// Example:
/// ```dart
/// final server = bluey.server();
/// if (server == null) {
///   print('Peripheral role not supported');
///   return;
/// }
///
/// // Add a service
/// server.addService(HostedService(
///   uuid: UUID.short(0x180F),
///   characteristics: [
///     HostedCharacteristic.readable(uuid: UUID.short(0x2A19)),
///   ],
/// ));
///
/// // Start advertising
/// await server.startAdvertising(name: 'My Device');
///
/// // Listen for connections
/// server.connections.listen((client) {
///   print('Client connected: ${client.id}');
/// });
/// ```
abstract class Server {
  /// The stable [ServerId] this server advertises through the lifecycle
  /// control service.
  ServerId get serverId;

  /// Whether advertising is currently active.
  bool get isAdvertising;

  /// Stream of connected client devices.
  ///
  /// Emits when a client connects to this peripheral. Emits for every
  /// central that connects, regardless of whether it speaks the Bluey
  /// lifecycle protocol.
  Stream<Client> get connections;

  /// Stream of clients that have identified themselves as Bluey peers.
  ///
  /// Emits a [PeerClient] the first time a connected central sends a
  /// lifecycle heartbeat write — signaling that the central speaks the
  /// Bluey protocol. Does not re-emit on subsequent heartbeats from the
  /// same client. On disconnect the identification resets; a
  /// reconnect-then-heartbeat produces a fresh emission.
  ///
  /// Consumers that only care about Bluey peers can subscribe here and
  /// ignore [connections]; raw / non-Bluey centrals are never emitted.
  Stream<PeerClient> get peerConnections;

  /// Stream of disconnected client device IDs.
  ///
  /// Emits the ID of a client when it disconnects from this peripheral.
  Stream<String> get disconnections;

  /// Currently connected clients.
  List<Client> get connectedClients;

  /// Add a service to the GATT database.
  ///
  /// Must be called before [startAdvertising].
  /// Throws if the GATT server cannot be opened or the service cannot be added.
  Future<void> addService(HostedService service);

  /// Remove a service by UUID.
  ///
  /// Cannot be called while advertising.
  ///
  /// Returns a [Future] that completes when the platform has acknowledged
  /// the removal. Errors from the platform are propagated.
  Future<void> removeService(UUID uuid);

  /// Start advertising.
  ///
  /// [name] - The device name to include in the advertisement. On iOS, this
  /// sets the local name in the advertisement packet (foreground only). On
  /// Android, the system Bluetooth adapter name is always used instead;
  /// this parameter is included in the scan response header but does not
  /// override the adapter name.
  /// [services] - Service UUIDs to include in the advertisement.
  /// [manufacturerData] - Manufacturer-specific data.
  /// [timeout] - Stop advertising after this duration.
  /// [mode] - Advertising mode (Android only). Controls the advertising
  /// interval and power consumption. Ignored on iOS, which manages
  /// intervals automatically. When `null` the platform applies its default.
  /// [peerDiscoverable] - When `true`, the Bluey lifecycle control service
  /// UUID is included in the advertising payload so other Bluey clients
  /// can find this server via `bluey.discoverPeers()`. Defaults to
  /// `false`. On Android the control UUID rides in the scan-response
  /// packet (a separate 31-byte buffer transmitted in response to active
  /// scans), leaving the primary 31-byte advertisement budget for
  /// [services] and [manufacturerData] (I313). On iOS the control UUID
  /// is folded into the unified advertisement and competes with
  /// [services] for primary-slot priority via CoreBluetooth's overflow
  /// ordering — the peer-discovery UUID is prepended so it stays in
  /// primary while user UUIDs land in overflow when the primary AD is
  /// full.
  ///
  /// Throws [AdvertisingException] if advertising fails.
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
    AdvertiseMode? mode,
    bool peerDiscoverable = false,
  });

  /// Stop advertising.
  Future<void> stopAdvertising();

  /// Send a notification to all subscribed clients.
  ///
  /// [characteristic] - The characteristic UUID to notify.
  /// [data] - The data to send.
  ///
  /// Returns after the notification is sent (with flow control).
  Future<void> notify(UUID characteristic, {required Uint8List data});

  /// Send a notification to a specific client.
  Future<void> notifyTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  });

  /// Send an indication to all subscribed clients.
  ///
  /// Unlike notifications, indications require acknowledgment from the client
  /// before returning. Use this for data that must be reliably delivered.
  ///
  /// [characteristic] - The characteristic UUID to indicate.
  /// [data] - The data to send.
  Future<void> indicate(UUID characteristic, {required Uint8List data});

  /// Send an indication to a specific client.
  ///
  /// Unlike notifications, indications require acknowledgment from the client
  /// before returning. Use this for data that must be reliably delivered.
  Future<void> indicateTo(
    Client client,
    UUID characteristic, {
    required Uint8List data,
  });

  /// Stream of read requests from clients.
  ///
  /// When a client reads a characteristic value, a [ReadRequest] is emitted.
  /// The server must respond using [respondToRead].
  Stream<ReadRequest> get readRequests;

  /// Stream of write requests from clients.
  ///
  /// When a client writes to a characteristic, a [WriteRequest] is emitted.
  /// If [WriteRequest.responseNeeded] is true, the server must respond using
  /// [respondToWrite].
  Stream<WriteRequest> get writeRequests;

  /// Respond to a read request.
  ///
  /// [request] - The read request to respond to.
  /// [status] - The GATT status for the response.
  /// [value] - The value to return (required for success status).
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  });

  /// Respond to a write request.
  ///
  /// [request] - The write request to respond to.
  /// [status] - The GATT status for the response.
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  });

  /// Dispose the server and release resources.
  Future<void> dispose();
}

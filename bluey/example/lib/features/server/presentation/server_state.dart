import 'package:bluey/bluey.dart';

/// State for the server feature.
class ServerScreenState {
  final bool isSupported;
  final AdvertisingState advertisingState;
  final List<Client> connectedClients;

  /// Addresses of currently-connected clients that have identified as Bluey
  /// peers (sent at least one lifecycle heartbeat). Cleared on
  /// disconnect; re-populated on reconnect-then-heartbeat. Used to
  /// render the BLUEY badge in the connected-clients list.
  final Set<ClientAddress> blueyPeerClientIds;

  final List<ServerLogEntry> log;
  final int notificationCount;
  final ServerId? serverId;
  final String? error;

  const ServerScreenState({
    this.isSupported = true,
    this.advertisingState = AdvertisingState.idle,
    this.connectedClients = const [],
    this.blueyPeerClientIds = const <ClientAddress>{},
    this.log = const [],
    this.notificationCount = 0,
    this.serverId,
    this.error,
  });

  /// Whether advertising is currently active. Derived from
  /// [advertisingState]. Kept for ergonomic convenience.
  bool get isAdvertising => advertisingState == AdvertisingState.advertising;

  /// Whether the given client has identified as a Bluey peer.
  bool isBlueyPeer(Client client) =>
      blueyPeerClientIds.contains(client.address);

  ServerScreenState copyWith({
    bool? isSupported,
    AdvertisingState? advertisingState,
    List<Client>? connectedClients,
    Set<ClientAddress>? blueyPeerClientIds,
    List<ServerLogEntry>? log,
    int? notificationCount,
    ServerId? serverId,
    String? error,
  }) {
    return ServerScreenState(
      isSupported: isSupported ?? this.isSupported,
      advertisingState: advertisingState ?? this.advertisingState,
      connectedClients: connectedClients ?? this.connectedClients,
      blueyPeerClientIds: blueyPeerClientIds ?? this.blueyPeerClientIds,
      log: log ?? this.log,
      notificationCount: notificationCount ?? this.notificationCount,
      serverId: serverId ?? this.serverId,
      error: error,
    );
  }
}

/// A log entry for server operations.
class ServerLogEntry {
  final String tag;
  final String message;
  final DateTime timestamp;

  ServerLogEntry(this.tag, this.message) : timestamp = DateTime.now();

  /// Creates a log entry from a [BlueyEvent], using the runtime type
  /// as the tag and [event.toString()] as the message.
  factory ServerLogEntry.fromBlueyEvent(BlueyEvent event) {
    return ServerLogEntry(event.runtimeType.toString(), event.toString());
  }
}

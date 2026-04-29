import 'package:bluey/bluey.dart';

/// State for the server feature.
class ServerScreenState {
  final bool isSupported;
  final bool isAdvertising;
  final List<Client> connectedClients;

  /// IDs of currently-connected clients that have identified as Bluey
  /// peers (sent at least one lifecycle heartbeat). Cleared on
  /// disconnect; re-populated on reconnect-then-heartbeat. Used to
  /// render the BLUEY badge in the connected-clients list.
  final Set<UUID> blueyPeerClientIds;

  final List<ServerLogEntry> log;
  final int notificationCount;
  final ServerId? serverId;
  final String? error;

  const ServerScreenState({
    this.isSupported = true,
    this.isAdvertising = false,
    this.connectedClients = const [],
    this.blueyPeerClientIds = const {},
    this.log = const [],
    this.notificationCount = 0,
    this.serverId,
    this.error,
  });

  /// Whether the given client has identified as a Bluey peer.
  bool isBlueyPeer(Client client) => blueyPeerClientIds.contains(client.id);

  ServerScreenState copyWith({
    bool? isSupported,
    bool? isAdvertising,
    List<Client>? connectedClients,
    Set<UUID>? blueyPeerClientIds,
    List<ServerLogEntry>? log,
    int? notificationCount,
    ServerId? serverId,
    String? error,
  }) {
    return ServerScreenState(
      isSupported: isSupported ?? this.isSupported,
      isAdvertising: isAdvertising ?? this.isAdvertising,
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
}

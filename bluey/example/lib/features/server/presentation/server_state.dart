import 'package:bluey/bluey.dart';

/// State for the server feature.
class ServerScreenState {
  final bool isSupported;
  final bool isAdvertising;
  final List<Client> connectedClients;
  final List<ServerLogEntry> log;
  final int notificationCount;
  final String? error;

  const ServerScreenState({
    this.isSupported = true,
    this.isAdvertising = false,
    this.connectedClients = const [],
    this.log = const [],
    this.notificationCount = 0,
    this.error,
  });

  ServerScreenState copyWith({
    bool? isSupported,
    bool? isAdvertising,
    List<Client>? connectedClients,
    List<ServerLogEntry>? log,
    int? notificationCount,
    String? error,
  }) {
    return ServerScreenState(
      isSupported: isSupported ?? this.isSupported,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      connectedClients: connectedClients ?? this.connectedClients,
      log: log ?? this.log,
      notificationCount: notificationCount ?? this.notificationCount,
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

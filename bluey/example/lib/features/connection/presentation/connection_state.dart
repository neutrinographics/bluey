import 'package:bluey/bluey.dart';

/// State for the connection feature.
class ConnectionScreenState {
  final Device device;
  final Connection? connection;
  final ConnectionState connectionState;
  final List<RemoteService>? services;
  final bool isDiscovering;
  final String? error;

  const ConnectionScreenState({
    required this.device,
    this.connection,
    this.connectionState = ConnectionState.disconnected,
    this.services,
    this.isDiscovering = false,
    this.error,
  });

  ConnectionScreenState copyWith({
    Device? device,
    Connection? connection,
    ConnectionState? connectionState,
    List<RemoteService>? services,
    bool? isDiscovering,
    String? error,
  }) {
    return ConnectionScreenState(
      device: device ?? this.device,
      connection: connection ?? this.connection,
      connectionState: connectionState ?? this.connectionState,
      services: services ?? this.services,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      error: error,
    );
  }

  /// Creates a copy with the connection cleared.
  ConnectionScreenState withoutConnection() {
    return ConnectionScreenState(
      device: device,
      connection: null,
      connectionState: ConnectionState.disconnected,
      services: null,
      isDiscovering: false,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionScreenState &&
        other.device == device &&
        other.connection == connection &&
        other.connectionState == connectionState &&
        _listEquals(other.services, services) &&
        other.isDiscovering == isDiscovering &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(
      device,
      connection,
      connectionState,
      services != null ? Object.hashAll(services!) : null,
      isDiscovering,
      error,
    );
  }

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

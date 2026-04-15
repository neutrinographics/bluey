import 'package:flutter/foundation.dart';

/// User-tunable options applied to the next [Connection].
@immutable
class ConnectionSettings {
  /// When true, the client requires the peer to host Bluey's lifecycle
  /// control service. See [Bluey.connect].
  final bool requireLifecycle;

  /// How many consecutive heartbeat write failures trigger a local
  /// disconnect. See [Bluey.connect].
  final int maxFailedHeartbeats;

  const ConnectionSettings({
    this.requireLifecycle = false,
    this.maxFailedHeartbeats = 1,
  });

  ConnectionSettings copyWith({
    bool? requireLifecycle,
    int? maxFailedHeartbeats,
  }) {
    return ConnectionSettings(
      requireLifecycle: requireLifecycle ?? this.requireLifecycle,
      maxFailedHeartbeats: maxFailedHeartbeats ?? this.maxFailedHeartbeats,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSettings &&
          runtimeType == other.runtimeType &&
          requireLifecycle == other.requireLifecycle &&
          maxFailedHeartbeats == other.maxFailedHeartbeats;

  @override
  int get hashCode => Object.hash(requireLifecycle, maxFailedHeartbeats);
}

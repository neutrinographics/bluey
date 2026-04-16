import 'package:flutter/foundation.dart';

/// User-tunable options applied to the next [Connection].
@immutable
class ConnectionSettings {
  /// How many consecutive heartbeat write failures trigger a local
  /// disconnect. See [Bluey.connect].
  final int maxFailedHeartbeats;

  const ConnectionSettings({
    this.maxFailedHeartbeats = 1,
  });

  ConnectionSettings copyWith({
    int? maxFailedHeartbeats,
  }) {
    return ConnectionSettings(
      maxFailedHeartbeats: maxFailedHeartbeats ?? this.maxFailedHeartbeats,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSettings &&
          runtimeType == other.runtimeType &&
          maxFailedHeartbeats == other.maxFailedHeartbeats;

  @override
  int get hashCode => maxFailedHeartbeats.hashCode;
}

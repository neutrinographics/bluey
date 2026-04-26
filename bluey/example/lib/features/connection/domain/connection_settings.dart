import 'package:flutter/foundation.dart';

/// User-tunable options applied to the next [Connection].
@immutable
class ConnectionSettings {
  /// How long after a peer-failure signal (heartbeat probe timeout or
  /// user-op timeout) without intervening successful activity before
  /// the connection is declared dead. See [Bluey.connect].
  final Duration peerSilenceTimeout;

  const ConnectionSettings({
    this.peerSilenceTimeout = const Duration(seconds: 30),
  });

  ConnectionSettings copyWith({Duration? peerSilenceTimeout}) {
    return ConnectionSettings(
      peerSilenceTimeout: peerSilenceTimeout ?? this.peerSilenceTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionSettings &&
          runtimeType == other.runtimeType &&
          peerSilenceTimeout == other.peerSilenceTimeout;

  @override
  int get hashCode => peerSilenceTimeout.hashCode;
}

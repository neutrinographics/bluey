import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// State for the service explorer screen.
class ServiceScreenState {
  final Connection connection;
  final RemoteService service;

  const ServiceScreenState({required this.connection, required this.service});
}

/// State for an individual characteristic card.
class CharacteristicState {
  final RemoteCharacteristic characteristic;

  /// Human-readable name sourced from the Characteristic User Description
  /// descriptor (0x2901), if present and successfully read.
  final String? userDescription;

  final Uint8List? value;
  final bool isReading;
  final bool isWriting;
  final bool isSubscribed;
  final List<LogEntry> log;
  final String? error;

  const CharacteristicState({
    required this.characteristic,
    this.userDescription,
    this.value,
    this.isReading = false,
    this.isWriting = false,
    this.isSubscribed = false,
    this.log = const [],
    this.error,
  });

  CharacteristicState copyWith({
    String? userDescription,
    Uint8List? value,
    bool? isReading,
    bool? isWriting,
    bool? isSubscribed,
    List<LogEntry>? log,
    String? error,
  }) {
    return CharacteristicState(
      characteristic: characteristic,
      userDescription: userDescription ?? this.userDescription,
      value: value ?? this.value,
      isReading: isReading ?? this.isReading,
      isWriting: isWriting ?? this.isWriting,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      log: log ?? this.log,
      error: error,
    );
  }
}

/// A log entry for characteristic operations.
class LogEntry {
  final String operation;
  final Uint8List value;
  final DateTime timestamp;

  LogEntry(this.operation, this.value) : timestamp = DateTime.now();
}

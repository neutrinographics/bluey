import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// State for the service/GATT screen.
class ServiceScreenState {
  final Connection connection;
  final RemoteService service;

  const ServiceScreenState({required this.connection, required this.service});
}

/// State for an individual characteristic card.
class CharacteristicState {
  final RemoteCharacteristic characteristic;
  final Uint8List? value;
  final bool isReading;
  final bool isWriting;
  final bool isSubscribed;
  final List<LogEntry> log;
  final String? error;

  const CharacteristicState({
    required this.characteristic,
    this.value,
    this.isReading = false,
    this.isWriting = false,
    this.isSubscribed = false,
    this.log = const [],
    this.error,
  });

  CharacteristicState copyWith({
    Uint8List? value,
    bool? isReading,
    bool? isWriting,
    bool? isSubscribed,
    List<LogEntry>? log,
    String? error,
  }) {
    return CharacteristicState(
      characteristic: characteristic,
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

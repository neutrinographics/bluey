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
  final Map<String, Uint8List> descriptorValues;
  final Set<String> readingDescriptors;
  final Set<String> failedDescriptors;

  const CharacteristicState({
    required this.characteristic,
    this.value,
    this.isReading = false,
    this.isWriting = false,
    this.isSubscribed = false,
    this.log = const [],
    this.error,
    this.descriptorValues = const {},
    this.readingDescriptors = const {},
    this.failedDescriptors = const {},
  });

  CharacteristicState copyWith({
    Uint8List? value,
    bool? isReading,
    bool? isWriting,
    bool? isSubscribed,
    List<LogEntry>? log,
    String? error,
    Map<String, Uint8List>? descriptorValues,
    Set<String>? readingDescriptors,
    Set<String>? failedDescriptors,
  }) {
    return CharacteristicState(
      characteristic: characteristic,
      value: value ?? this.value,
      isReading: isReading ?? this.isReading,
      isWriting: isWriting ?? this.isWriting,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      log: log ?? this.log,
      error: error,
      descriptorValues: descriptorValues ?? this.descriptorValues,
      readingDescriptors: readingDescriptors ?? this.readingDescriptors,
      failedDescriptors: failedDescriptors ?? this.failedDescriptors,
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

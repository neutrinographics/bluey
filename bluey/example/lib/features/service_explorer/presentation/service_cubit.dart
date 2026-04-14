import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../application/read_characteristic.dart';
import '../application/write_characteristic.dart';
import '../application/subscribe_to_characteristic.dart';
import '../application/read_descriptor.dart';
import 'service_state.dart';

/// Cubit for managing a single characteristic's state.
class CharacteristicCubit extends Cubit<CharacteristicState> {
  final ReadCharacteristic _readCharacteristic;
  final WriteCharacteristic _writeCharacteristic;
  final SubscribeToCharacteristic _subscribeToCharacteristic;
  final ReadDescriptor _readDescriptor;

  StreamSubscription<Uint8List>? _notificationSubscription;

  CharacteristicCubit({
    required RemoteCharacteristic characteristic,
    required ReadCharacteristic readCharacteristic,
    required WriteCharacteristic writeCharacteristic,
    required SubscribeToCharacteristic subscribeToCharacteristic,
    required ReadDescriptor readDescriptor,
  }) : _readCharacteristic = readCharacteristic,
       _writeCharacteristic = writeCharacteristic,
       _subscribeToCharacteristic = subscribeToCharacteristic,
       _readDescriptor = readDescriptor,
       super(CharacteristicState(characteristic: characteristic)) {
    _autoReadUserDescription();
  }

  /// Silently reads the Characteristic User Description descriptor (0x2901)
  /// and stores its UTF-8 value as the display name. Failures are ignored.
  void _autoReadUserDescription() async {
    final descriptor = state.characteristic.descriptors
        .where((d) => d.uuid == Descriptors.characteristicUserDescription)
        .firstOrNull;
    if (descriptor == null) return;
    try {
      final bytes = await _readDescriptor(descriptor);
      final name = utf8.decode(bytes, allowMalformed: true).trim();
      if (name.isNotEmpty && !isClosed) {
        emit(state.copyWith(userDescription: name));
      }
    } catch (_) {
      // Non-fatal — descriptor read failure does not affect characteristic use.
    }
  }

  /// Reads the characteristic value.
  Future<void> read() async {
    emit(state.copyWith(isReading: true, error: null));

    try {
      final value = await _readCharacteristic(state.characteristic);
      final newLog = [LogEntry('Read', value), ...state.log];
      if (newLog.length > 100) newLog.removeLast();

      emit(state.copyWith(value: value, isReading: false, log: newLog));
    } catch (e) {
      emit(state.copyWith(isReading: false, error: 'Read failed: $e'));
    }
  }

  /// Writes a value to the characteristic.
  Future<void> write(Uint8List value) async {
    emit(state.copyWith(isWriting: true, error: null));

    try {
      final withResponse = state.characteristic.properties.canWrite;
      await _writeCharacteristic(
        state.characteristic,
        value,
        withResponse: withResponse,
      );

      final newLog = [LogEntry('Write', value), ...state.log];
      if (newLog.length > 100) newLog.removeLast();

      emit(state.copyWith(isWriting: false, log: newLog));
    } catch (e) {
      emit(state.copyWith(isWriting: false, error: 'Write failed: $e'));
    }
  }

  /// Toggles notification subscription.
  void toggleNotifications() {
    if (state.isSubscribed) {
      _unsubscribe();
    } else {
      _subscribe();
    }
  }

  void _subscribe() {
    _notificationSubscription = _subscribeToCharacteristic(
      state.characteristic,
    ).listen(
      (value) {
        final newLog = [LogEntry('Notify', value), ...state.log];
        if (newLog.length > 100) newLog.removeLast();

        emit(state.copyWith(value: value, log: newLog));
      },
      onError: (error) {
        emit(
          state.copyWith(
            isSubscribed: false,
            error: 'Notification error: $error',
          ),
        );
      },
    );
    emit(state.copyWith(isSubscribed: true));
  }

  void _unsubscribe() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    emit(state.copyWith(isSubscribed: false));
  }

  /// Clears the operation log.
  void clearLog() {
    emit(state.copyWith(log: []));
  }

  /// Clears any error message.
  void clearError() {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _notificationSubscription?.cancel();
    return super.close();
  }
}

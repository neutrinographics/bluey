import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bluey/bluey.dart';

import '../domain/use_cases/read_characteristic.dart';
import '../domain/use_cases/write_characteristic.dart';
import '../domain/use_cases/subscribe_to_characteristic.dart';
import '../domain/use_cases/read_descriptor.dart';
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
       super(CharacteristicState(characteristic: characteristic));

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

  /// Reads a descriptor value.
  Future<Uint8List?> readDescriptorValue(RemoteDescriptor descriptor) async {
    try {
      return await _readDescriptor(descriptor);
    } catch (e) {
      emit(state.copyWith(error: 'Descriptor read failed: $e'));
      return null;
    }
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

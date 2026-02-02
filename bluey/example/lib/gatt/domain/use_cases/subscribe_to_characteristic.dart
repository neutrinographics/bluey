import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../gatt_repository.dart';

/// Use case for subscribing to characteristic notifications/indications.
class SubscribeToCharacteristic {
  final GattRepository _repository;

  SubscribeToCharacteristic(this._repository);

  /// Subscribes to notifications/indications from the specified [characteristic].
  ///
  /// Returns a stream of values received from the characteristic.
  /// The subscription is automatically managed - it starts when the stream
  /// is listened to and stops when the subscription is cancelled.
  Stream<Uint8List> call(RemoteCharacteristic characteristic) {
    return _repository.subscribeToCharacteristic(characteristic);
  }
}

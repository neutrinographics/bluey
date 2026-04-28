import 'dart:async';
import 'dart:typed_data';

import 'package:bluey/bluey.dart';

/// Per-test programmable characteristic. Tests configure
/// `onWriteHook`/`onReadHook`/`emitNotification` to model the server side.
class FakeRemoteCharacteristic implements RemoteCharacteristic {
  @override
  final UUID uuid;
  @override
  final AttributeHandle handle;
  @override
  final CharacteristicProperties properties;

  /// Called for each write. Default: succeed with no side effects.
  /// Override to inject delays or throws.
  Future<void> Function(Uint8List value, {required bool withResponse})
      onWriteHook = (_, {required bool withResponse}) async {};

  /// Called for each read. Default: returns empty bytes.
  Future<Uint8List> Function() onReadHook = () async => Uint8List(0);

  final _notif = StreamController<Uint8List>.broadcast();

  FakeRemoteCharacteristic({
    required this.uuid,
    AttributeHandle? handle,
    this.properties = const CharacteristicProperties(
      canRead: true,
      canWrite: true,
      canWriteWithoutResponse: true,
      canNotify: true,
    ),
  }) : handle = handle ?? AttributeHandle(1);

  /// Inject a notification to subscribers.
  void emitNotification(Uint8List value) => _notif.add(value);

  @override
  Future<Uint8List> read() => onReadHook();

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) =>
      onWriteHook(value, withResponse: withResponse);

  @override
  Stream<Uint8List> get notifications => _notif.stream;

  @override
  RemoteDescriptor descriptor(UUID uuid) =>
      throw UnimplementedError('FakeRemoteCharacteristic.descriptor');

  @override
  List<RemoteDescriptor> get descriptors => const [];
}

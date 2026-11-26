import '../../connection/bluey_connection.dart';
import '../../features/connection/application/link_session.dart';
import '../../gatt_client/gatt.dart';
import '../../shared/domain/device_address.dart';
import '../../shared/uuid.dart';
import 'android_connection_extensions.dart';
import 'connection.dart';
import 'connection_failure_translation.dart';
import 'connection_state_translation.dart';
import 'ios_connection_extensions.dart';

/// One link's session presented as the public Connection.
///
/// The session is the only holder of the link's state, so this reads the
/// link and never keeps a copy: a Connection whose link ended stays ended,
/// whatever the platform later says about the same device.
final class BlueyConnection implements Connection {
  /// Presents [session], whose GATT operations [gatt] carries.
  BlueyConnection({required LinkSession session, required LinkGattClient gatt})
    : _session = session,
      _gatt = gatt;

  final LinkSession _session;
  final LinkGattClient _gatt;

  @override
  DeviceAddress get deviceAddress => _session.link.device;

  @override
  ConnectionState get state => connectionStateOf(_session.phase);

  /// Gives each listener the current state first, since a listener that
  /// arrives late must still see where the link stands, and closes once the
  /// link has ended.
  @override
  Stream<ConnectionState> get stateChanges =>
      Stream<ConnectionState>.multi((controller) {
        controller.add(state);
        if (_session.link.hasEnded) {
          controller.closeSync();
          return;
        }
        final phases = _session.phases.listen(
          (phase) => controller.add(connectionStateOf(phase)),
          onDone: controller.closeSync,
        );
        controller.onCancel = phases.cancel;
      }, isBroadcast: true);

  @override
  Stream<List<RemoteService>> get servicesChanges => _gatt.servicesChanges;

  @override
  RemoteService service(UUID uuid) => _gatt.service(uuid);

  @override
  Future<List<RemoteService>> services({bool cache = false}) =>
      _gatt.services(cache: cache);

  @override
  Future<bool> hasService(UUID uuid) => _gatt.hasService(uuid);

  @override
  Future<WritePayloadLimit> maxWritePayload({required bool withResponse}) =>
      _gatt.maxWritePayload(withResponse: withResponse);

  @override
  Future<int> readRssi() => _gatt.readRssi();

  @override
  Future<void> disconnect() async =>
      valueOrThrow(await _session.disconnect(), device: deviceAddress);

  @override
  AndroidConnectionExtensions? get android => _gatt.android;

  @override
  IosConnectionExtensions? get ios => _gatt.ios;
}

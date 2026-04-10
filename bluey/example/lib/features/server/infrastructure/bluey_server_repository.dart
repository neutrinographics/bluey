import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Implementation of [ServerRepository] using the Bluey library.
class BlueyServerRepository implements ServerRepository {
  final Bluey _bluey;
  Server? _server;

  BlueyServerRepository(this._bluey);

  @override
  Server? getServer() {
    _server ??= _bluey.server();
    return _server;
  }

  @override
  Future<void> startAdvertising({
    String? name,
    List<UUID>? services,
    ManufacturerData? manufacturerData,
    Duration? timeout,
  }) async {
    final server = getServer();
    if (server == null) {
      throw UnsupportedError('Server not supported on this platform');
    }
    await server.startAdvertising(
      name: name,
      services: services,
      manufacturerData: manufacturerData,
      timeout: timeout,
    );
  }

  @override
  Future<void> stopAdvertising() async {
    await _server?.stopAdvertising();
  }

  @override
  Future<void> addService(HostedService service) async {
    final server = getServer();
    if (server == null) {
      throw UnsupportedError('Server not supported on this platform');
    }
    await server.addService(service);
  }

  @override
  Future<void> notify(UUID characteristicUuid, Uint8List data) async {
    await _server?.notify(characteristicUuid, data: data);
  }

  @override
  Stream<Central> get connections {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.connections;
  }

  @override
  Future<void> disconnectCentral(Central central) async {
    await central.disconnect();
  }

  @override
  Future<void> dispose() async {
    await _server?.dispose();
    _server = null;
  }
}

import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Implementation of [ServerRepository] using the Bluey library.
class BlueyServerRepository implements ServerRepository {
  final Bluey _bluey;
  Server? _server;

  ServerId? _identity;

  BlueyServerRepository(this._bluey);

  @override
  void setIdentity(ServerId identity) {
    _identity = identity;
  }

  @override
  Server? getServer() {
    _server ??= _bluey.server(identity: _identity);
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
  Stream<Client> get connections {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.connections;
  }

  @override
  Stream<PeerClient> get peerConnections {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.peerConnections;
  }

  @override
  Stream<String> get disconnections {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.disconnections;
  }

  @override
  List<Client> get connectedClients {
    return getServer()?.connectedClients ?? [];
  }

  @override
  Stream<ReadRequest> get readRequests {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.readRequests;
  }

  @override
  Stream<WriteRequest> get writeRequests {
    final server = getServer();
    if (server == null) {
      return const Stream.empty();
    }
    return server.writeRequests;
  }

  @override
  Future<void> respondToRead(
    ReadRequest request, {
    required GattResponseStatus status,
    Uint8List? value,
  }) async {
    await getServer()?.respondToRead(request, status: status, value: value);
  }

  @override
  Future<void> respondToWrite(
    WriteRequest request, {
    required GattResponseStatus status,
  }) async {
    await getServer()?.respondToWrite(request, status: status);
  }

  @override
  Future<Server?> resetServer({required ServerId identity}) async {
    await _server?.dispose();
    _server = null;
    _identity = identity;
    return getServer();
  }

  @override
  Future<void> dispose() async {
    await _server?.dispose();
    _server = null;
  }
}

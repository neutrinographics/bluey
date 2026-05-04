import 'dart:typed_data';

import 'package:bluey/bluey.dart';

import '../domain/server_repository.dart';

/// Implementation of [ServerRepository] using the Bluey library.
///
/// Shares the app-wide [Bluey] singleton, which is constructed at app
/// startup with the persisted local identity (see
/// `service_locator.dart` and `main.dart`). [setIdentity] is therefore
/// only meaningful when the requested identity already matches the
/// shared instance's `localIdentity`; rotating identity at runtime
/// requires an app restart.
class BlueyServerRepository implements ServerRepository {
  final Bluey _bluey;
  Server? _server;

  BlueyServerRepository(this._bluey);

  @override
  void setIdentity(ServerId identity) {
    // No-op at the repository level: identity is fixed at Bluey
    // construction time. The cubit persists the new value through
    // [ServerIdentityStorage] so the next app launch picks it up.
  }

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
    // Identity is fixed at Bluey construction time. The cubit has
    // already persisted the new identity; an app restart is required
    // to apply it. Dispose the current server to leave the runtime in
    // a clean state until then.
    await _server?.dispose();
    _server = null;
    return null;
  }

  @override
  Future<void> dispose() async {
    await _server?.dispose();
    _server = null;
  }
}

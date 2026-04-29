import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stub [Client] that records calls to [disconnect] for the
/// delegation tests below.
class _SpyClient implements Client {
  _SpyClient({required this.id, required this.mtu});

  @override
  final UUID id;

  @override
  final int mtu;

  bool disconnectCalled = false;

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
  }
}

void main() {
  group('PeerClient', () {
    test('create() wraps a Client (identity)', () {
      final client = _SpyClient(id: UUID.short(0xAAAA), mtu: 23);
      final peer = PeerClient.create(client: client);
      expect(identical(peer.client, client), isTrue);
    });

    test('exposes the underlying client unchanged', () {
      final client = _SpyClient(id: UUID.short(0xBBBB), mtu: 247);
      final peer = PeerClient.create(client: client);
      expect(peer.client.id, equals(UUID.short(0xBBBB)));
      expect(peer.client.mtu, equals(247));
    });

    test('two PeerClients wrapping the same client are equal', () {
      final client = _SpyClient(id: UUID.short(0xCCCC), mtu: 23);
      final a = PeerClient.create(client: client);
      final b = PeerClient.create(client: client);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two PeerClients wrapping different clients are not equal', () {
      final c1 = _SpyClient(id: UUID.short(0xDDDD), mtu: 23);
      final c2 = _SpyClient(id: UUID.short(0xEEEE), mtu: 23);
      final a = PeerClient.create(client: c1);
      final b = PeerClient.create(client: c2);
      expect(a, isNot(equals(b)));
    });
  });
}

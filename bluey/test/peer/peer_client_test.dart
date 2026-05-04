import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stub [Client] used by the identity / equality tests below.
class _SpyClient implements Client {
  _SpyClient({required this.id, required this.mtu});

  @override
  final UUID id;

  @override
  final int mtu;
}

void main() {
  final senderA = ServerId('11111111-1111-4111-8111-111111111111');
  final senderB = ServerId('22222222-2222-4222-8222-222222222222');

  group('PeerClient', () {
    test('create() wraps a Client (identity)', () {
      final client = _SpyClient(id: UUID.short(0xAAAA), mtu: 23);
      final peer = PeerClient.create(client: client, serverId: senderA);
      expect(identical(peer.client, client), isTrue);
    });

    test('exposes the underlying client and serverId unchanged', () {
      final client = _SpyClient(id: UUID.short(0xBBBB), mtu: 247);
      final peer = PeerClient.create(client: client, serverId: senderA);
      expect(peer.client.id, equals(UUID.short(0xBBBB)));
      expect(peer.client.mtu, equals(247));
      expect(peer.serverId, equals(senderA));
    });

    test('two PeerClients wrapping the same client + serverId are equal', () {
      final client = _SpyClient(id: UUID.short(0xCCCC), mtu: 23);
      final a = PeerClient.create(client: client, serverId: senderA);
      final b = PeerClient.create(client: client, serverId: senderA);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two PeerClients wrapping different clients are not equal', () {
      final c1 = _SpyClient(id: UUID.short(0xDDDD), mtu: 23);
      final c2 = _SpyClient(id: UUID.short(0xEEEE), mtu: 23);
      final a = PeerClient.create(client: c1, serverId: senderA);
      final b = PeerClient.create(client: c2, serverId: senderA);
      expect(a, isNot(equals(b)));
    });

    test('two PeerClients with different serverIds are not equal', () {
      final client = _SpyClient(id: UUID.short(0xFFFF), mtu: 23);
      final a = PeerClient.create(client: client, serverId: senderA);
      final b = PeerClient.create(client: client, serverId: senderB);
      expect(a, isNot(equals(b)));
    });
  });
}

import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey/src/lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LifecycleCodec — heartbeat / disconnect messages', () {
    const codec = LifecycleCodec();

    test(
      'encodes a Heartbeat as version + alive marker + 16-byte ServerId',
      () {
        final id = ServerId('11111111-2222-3333-4444-555555555555');
        final bytes = codec.encodeMessage(Heartbeat(id));
        expect(bytes, hasLength(18));
        expect(bytes[0], protocolVersion);
        expect(bytes[1], 0x01);
        expect(bytes.sublist(2, 18), id.toBytes());
      },
    );

    test('encodes a CourtesyDisconnect with the disconnect marker', () {
      final id = ServerId('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final bytes = codec.encodeMessage(CourtesyDisconnect(id));
      expect(bytes, hasLength(18));
      expect(bytes[0], protocolVersion);
      expect(bytes[1], 0x00);
      expect(bytes.sublist(2, 18), id.toBytes());
    });

    test('Heartbeat round-trip preserves senderId', () {
      final id = ServerId.generate();
      final decoded = codec.decodeMessage(codec.encodeMessage(Heartbeat(id)));
      expect(decoded, isA<Heartbeat>());
      expect((decoded as Heartbeat).senderId, equals(id));
    });

    test('CourtesyDisconnect round-trip preserves senderId', () {
      final id = ServerId.generate();
      final decoded = codec.decodeMessage(
        codec.encodeMessage(CourtesyDisconnect(id)),
      );
      expect(decoded, isA<CourtesyDisconnect>());
      expect((decoded as CourtesyDisconnect).senderId, equals(id));
    });

    test('rejects payloads of the wrong length', () {
      final tooShort = Uint8List.fromList([protocolVersion, 0x01]);
      expect(
        () => codec.decodeMessage(tooShort),
        throwsA(isA<MalformedLifecycleMessage>()),
      );

      final tooLong = Uint8List(19)..[0] = protocolVersion;
      expect(
        () => codec.decodeMessage(tooLong),
        throwsA(isA<MalformedLifecycleMessage>()),
      );

      expect(
        () => codec.decodeMessage(Uint8List(0)),
        throwsA(isA<MalformedLifecycleMessage>()),
      );
    });

    test('rejects unknown protocol versions with a typed exception', () {
      final bytes = Uint8List(18);
      bytes[0] = 0xFE; // unknown version
      bytes[1] = 0x01;
      expect(
        () => codec.decodeMessage(bytes),
        throwsA(
          isA<UnsupportedLifecycleProtocolVersion>().having(
            (e) => e.version,
            'version',
            0xFE,
          ),
        ),
      );
    });

    test('rejects unknown markers with a malformed exception', () {
      final bytes = Uint8List(18);
      bytes[0] = protocolVersion;
      bytes[1] = 0x77; // unknown marker
      expect(
        () => codec.decodeMessage(bytes),
        throwsA(isA<MalformedLifecycleMessage>()),
      );
    });
  });

  group('LifecycleCodec — advertised identity', () {
    const codec = LifecycleCodec();

    test('encodes the advertised identity as version + 16-byte ServerId', () {
      final id = ServerId('11111111-2222-3333-4444-555555555555');
      final bytes = codec.encodeAdvertisedIdentity(id);
      expect(bytes, hasLength(17));
      expect(bytes[0], protocolVersion);
      expect(bytes.sublist(1, 17), id.toBytes());
    });

    test('round-trips through decodeAdvertisedIdentity', () {
      final id = ServerId.generate();
      final bytes = codec.encodeAdvertisedIdentity(id);
      expect(codec.decodeAdvertisedIdentity(bytes), equals(id));
    });

    test('rejects wrong length', () {
      expect(
        () => codec.decodeAdvertisedIdentity(Uint8List(16)),
        throwsA(isA<MalformedLifecycleMessage>()),
      );
    });

    test('rejects unknown versions', () {
      final bytes = Uint8List(17);
      bytes[0] = 0x42;
      expect(
        () => codec.decodeAdvertisedIdentity(bytes),
        throwsA(isA<UnsupportedLifecycleProtocolVersion>()),
      );
    });
  });
}

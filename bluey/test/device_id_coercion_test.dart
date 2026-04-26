import 'package:bluey/bluey.dart';
import 'package:bluey/src/shared/device_id_coercion.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the platform-device-id → UUID coercion helper.
///
/// Background: Android uses MAC addresses as device identifiers
/// (e.g. "AA:BB:CC:DD:EE:FF"); iOS uses UUIDs directly. The library's
/// domain-level [Device.id] is a [UUID], so the platform identifier
/// must be coerced into UUID form. Pre-I057, this coercion was
/// duplicated byte-identical in `bluey.dart` (`_deviceIdToUuid`) and
/// `peer_discovery.dart` (`_addressToUuid`). I057 extracts the
/// shared helper.
///
/// Note: the underlying coercion is a workaround flagged by I006
/// (typed identifier). I057 only consolidates the duplication so a
/// future I006 fix has a single site to rewrite.
void main() {
  group('deviceIdToUuid', () {
    test('passes through an already-UUID-shaped iOS-style id unchanged', () {
      final result = deviceIdToUuid('aabbccdd-eeff-0011-2233-445566778899');
      expect(result, equals(UUID('aabbccdd-eeff-0011-2233-445566778899')));
    });

    test('strips colons and pads an Android MAC address', () {
      final result = deviceIdToUuid('AA:BB:CC:DD:EE:FF');
      // 12 hex chars from MAC, left-padded with 20 zeros to 32 hex chars,
      // then formatted as a UUID string.
      expect(result.toString(), equals('00000000-0000-0000-0000-aabbccddeeff'));
    });

    test('lowercases hex digits in the MAC path', () {
      final lower = deviceIdToUuid('aa:bb:cc:dd:ee:ff');
      final upper = deviceIdToUuid('AA:BB:CC:DD:EE:FF');
      expect(lower, equals(upper));
    });

    test('handles a colonless MAC-like address', () {
      // Treated as MAC-format input: clean of colons, pad to 32, build UUID.
      final result = deviceIdToUuid('aabbccddeeff');
      expect(result.toString(), equals('00000000-0000-0000-0000-aabbccddeeff'));
    });

    test('UUID-format detection requires both length 36 and a hyphen', () {
      // 36-char hyphen-bearing input → treated as UUID, passes through.
      final asUuid = deviceIdToUuid('00000000-0000-0000-0000-aabbccddeeff');
      expect(
        asUuid.toString(),
        equals('00000000-0000-0000-0000-aabbccddeeff'),
      );
    });
  });
}

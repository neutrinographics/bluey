import 'package:bluey/src/features/platform/domain/capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = Capabilities(platformKind: PlatformKind.other);

  group('Capabilities', () {
    test('two with the same flags are equal, and hash alike', () {
      // arrange
      const a = Capabilities(platformKind: PlatformKind.ios, maxMtu: 185);
      const b = Capabilities(platformKind: PlatformKind.ios, maxMtu: 185);

      // assert
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a matrix is equal to itself', () {
      expect(Capabilities.fake, same(Capabilities.fake));
      expect(Capabilities.fake == Capabilities.fake, isTrue);
    });

    test('is not equal to another kind of object', () {
      expect(base == Object(), isFalse);
    });

    final variants = <String, Capabilities>{
      'platformKind': const Capabilities(platformKind: PlatformKind.android),
      'canScan': const Capabilities(
        platformKind: PlatformKind.other,
        canScan: false,
      ),
      'canConnect': const Capabilities(
        platformKind: PlatformKind.other,
        canConnect: false,
      ),
      'canAdvertise': const Capabilities(
        platformKind: PlatformKind.other,
        canAdvertise: true,
      ),
      'canRequestMtu': const Capabilities(
        platformKind: PlatformKind.other,
        canRequestMtu: true,
      ),
      'maxMtu': const Capabilities(
        platformKind: PlatformKind.other,
        maxMtu: 185,
      ),
      'canScanInBackground': const Capabilities(
        platformKind: PlatformKind.other,
        canScanInBackground: true,
      ),
      'canAdvertiseInBackground': const Capabilities(
        platformKind: PlatformKind.other,
        canAdvertiseInBackground: true,
      ),
      'canBond': const Capabilities(
        platformKind: PlatformKind.other,
        canBond: true,
      ),
      'canRequestPhy': const Capabilities(
        platformKind: PlatformKind.other,
        canRequestPhy: true,
      ),
      'canRequestConnectionParameters': const Capabilities(
        platformKind: PlatformKind.other,
        canRequestConnectionParameters: true,
      ),
      'canRequestEnable': const Capabilities(
        platformKind: PlatformKind.other,
        canRequestEnable: true,
      ),
      'canAdvertiseManufacturerData': const Capabilities(
        platformKind: PlatformKind.other,
        canAdvertiseManufacturerData: true,
      ),
      'reportsCentralDisconnects': const Capabilities(
        platformKind: PlatformKind.other,
        reportsCentralDisconnects: true,
      ),
    };
    for (final MapEntry(key: flag, value: variant) in variants.entries) {
      test('differs when $flag differs', () => expect(variant, isNot(base)));
    }

    test(
      'the defaults are those of a platform that only scans and connects',
      () {
        expect(base.canScan, isTrue);
        expect(base.canConnect, isTrue);
        expect(base.canAdvertise, isFalse);
        expect(base.canRequestMtu, isFalse);
        expect(base.maxMtu, 23);
        expect(base.canScanInBackground, isFalse);
        expect(base.canAdvertiseInBackground, isFalse);
        expect(base.canBond, isFalse);
        expect(base.canRequestPhy, isFalse);
        expect(base.canRequestConnectionParameters, isFalse);
        expect(base.canRequestEnable, isFalse);
        expect(base.canAdvertiseManufacturerData, isFalse);
        expect(base.reportsCentralDisconnects, isFalse);
      },
    );

    test('names every flag when printed', () {
      expect(
        Capabilities.iOS.toString(),
        'Capabilities(platformKind: PlatformKind.ios, canScan: true, '
        'canConnect: true, canAdvertise: true, canRequestMtu: false, '
        'maxMtu: 185, canScanInBackground: true, '
        'canAdvertiseInBackground: true, canBond: false, '
        'canRequestPhy: false, canRequestConnectionParameters: false, '
        'canRequestEnable: false, canAdvertiseManufacturerData: false, '
        'reportsCentralDisconnects: true)',
      );
    });
  });
}

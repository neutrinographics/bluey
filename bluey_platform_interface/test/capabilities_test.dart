import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_platform_interface/src/capabilities.dart';

void main() {
  group('Capabilities', () {
    test('creates with all fields', () {
      const capabilities = Capabilities(
        platformKind: PlatformKind.fake,
        canScan: true,
        canConnect: true,
        canAdvertise: true,
        canRequestMtu: true,
        maxMtu: 517,
        canScanInBackground: false,
        canAdvertiseInBackground: false,
        canBond: true,
        canRequestPhy: true,
        canRequestConnectionParameters: true,
        canRequestEnable: true,
      );

      expect(capabilities.canScan, isTrue);
      expect(capabilities.canConnect, isTrue);
      expect(capabilities.canAdvertise, isTrue);
      expect(capabilities.canRequestMtu, isTrue);
      expect(capabilities.maxMtu, equals(517));
      expect(capabilities.canScanInBackground, isFalse);
      expect(capabilities.canAdvertiseInBackground, isFalse);
      expect(capabilities.canBond, isTrue);
      expect(capabilities.canRequestPhy, isTrue);
      expect(capabilities.canRequestConnectionParameters, isTrue);
      expect(capabilities.canRequestEnable, isTrue);
    });

    test('creates with defaults', () {
      const capabilities = Capabilities(platformKind: PlatformKind.fake);

      expect(capabilities.canScan, isTrue);
      expect(capabilities.canConnect, isTrue);
      expect(capabilities.canAdvertise, isFalse);
      expect(capabilities.canRequestMtu, isFalse);
      expect(capabilities.maxMtu, equals(23));
      expect(capabilities.canScanInBackground, isFalse);
      expect(capabilities.canAdvertiseInBackground, isFalse);
      expect(capabilities.canBond, isFalse);
      expect(capabilities.canRequestPhy, isFalse);
      expect(capabilities.canRequestConnectionParameters, isFalse);
      expect(capabilities.canRequestEnable, isFalse);
    });

    test('android capabilities', () {
      expect(Capabilities.android.canAdvertise, isTrue);
      expect(Capabilities.android.canRequestMtu, isTrue);
      expect(Capabilities.android.maxMtu, equals(517));
      // I035 Stage A: canBond, canRequestPhy, and
      // canRequestConnectionParameters are all false until the Dart-side
      // bond/PHY/conn-param methods are wired through Pigeon (Stage B).
      // The domain layer (BlueyConnection) consults these flags before
      // subscribing to or fetching the corresponding state.
      expect(Capabilities.android.canBond, isFalse);
      expect(Capabilities.android.canRequestPhy, isFalse);
      expect(Capabilities.android.canRequestConnectionParameters, isFalse);
      expect(Capabilities.android.canRequestEnable, isTrue);
    });

    test('iOS capabilities', () {
      expect(Capabilities.iOS.canAdvertise, isTrue);
      expect(Capabilities.iOS.maxMtu, equals(185));
      expect(Capabilities.iOS.canScanInBackground, isTrue);
      expect(Capabilities.iOS.canAdvertiseInBackground, isTrue);
      // CoreBluetooth does not expose bond / PHY / connection parameters;
      // see I200 wontfix.
      expect(Capabilities.iOS.canBond, isFalse);
      expect(Capabilities.iOS.canRequestPhy, isFalse);
      expect(Capabilities.iOS.canRequestConnectionParameters, isFalse);
      expect(Capabilities.iOS.canRequestEnable, isFalse);
    });

    test('macOS capabilities', () {
      expect(Capabilities.macOS.canAdvertise, isTrue);
      expect(Capabilities.macOS.maxMtu, equals(185));
      expect(Capabilities.macOS.canRequestEnable, isFalse);
    });

    test('windows capabilities', () {
      expect(Capabilities.windows.canRequestMtu, isTrue);
      expect(Capabilities.windows.maxMtu, equals(517));
      expect(Capabilities.windows.canAdvertise, isFalse);
    });

    test('linux capabilities', () {
      expect(Capabilities.linux.canAdvertise, isTrue);
      expect(Capabilities.linux.canRequestMtu, isTrue);
      expect(Capabilities.linux.maxMtu, equals(517));
    });

    test('is immutable value object', () {
      const cap1 = Capabilities.android;
      const cap2 = Capabilities.android;

      expect(cap1, equals(cap2));
      expect(cap1.hashCode, equals(cap2.hashCode));
    });
  });

  group('PlatformKind discriminator', () {
    test('Capabilities.android has platformKind=android', () {
      expect(Capabilities.android.platformKind, PlatformKind.android);
    });

    test('Capabilities.iOS has platformKind=ios', () {
      expect(Capabilities.iOS.platformKind, PlatformKind.ios);
    });

    test('Capabilities.fake has platformKind=fake', () {
      expect(Capabilities.fake.platformKind, PlatformKind.fake);
    });

    test('macOS / windows / linux presets have platformKind=other', () {
      expect(Capabilities.macOS.platformKind, PlatformKind.other);
      expect(Capabilities.windows.platformKind, PlatformKind.other);
      expect(Capabilities.linux.platformKind, PlatformKind.other);
    });

    test('two Capabilities differing only in platformKind are not equal', () {
      const a = Capabilities(platformKind: PlatformKind.android);
      const b = Capabilities(platformKind: PlatformKind.ios);
      expect(a == b, isFalse);
    });
  });

  group('canAdvertiseManufacturerData', () {
    test('Capabilities.android sets canAdvertiseManufacturerData=true', () {
      expect(Capabilities.android.canAdvertiseManufacturerData, isTrue);
    });

    test('Capabilities.iOS sets canAdvertiseManufacturerData=false', () {
      expect(Capabilities.iOS.canAdvertiseManufacturerData, isFalse);
    });

    test('default constructor sets canAdvertiseManufacturerData=false', () {
      const c = Capabilities(platformKind: PlatformKind.other);
      expect(c.canAdvertiseManufacturerData, isFalse);
    });

    test('two Capabilities differing only in canAdvertiseManufacturerData are not equal', () {
      const a = Capabilities(
        platformKind: PlatformKind.other,
        canAdvertiseManufacturerData: true,
      );
      const b = Capabilities(
        platformKind: PlatformKind.other,
        canAdvertiseManufacturerData: false,
      );
      expect(a == b, isFalse);
    });
  });
}

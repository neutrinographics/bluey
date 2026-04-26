import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_platform_interface/src/capabilities.dart';

void main() {
  group('Capabilities', () {
    test('creates with all fields', () {
      const capabilities = Capabilities(
        canScan: true,
        canConnect: true,
        canAdvertise: true,
        canRequestMtu: true,
        maxMtu: 517,
        canScanInBackground: false,
        canAdvertiseInBackground: false,
        canBond: true,
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
      expect(capabilities.canRequestEnable, isTrue);
    });

    test('creates with defaults', () {
      const capabilities = Capabilities();

      expect(capabilities.canScan, isTrue);
      expect(capabilities.canConnect, isTrue);
      expect(capabilities.canAdvertise, isFalse);
      expect(capabilities.canRequestMtu, isFalse);
      expect(capabilities.maxMtu, equals(23));
      expect(capabilities.canScanInBackground, isFalse);
      expect(capabilities.canAdvertiseInBackground, isFalse);
      expect(capabilities.canBond, isFalse);
      expect(capabilities.canRequestEnable, isFalse);
    });

    test('android capabilities', () {
      expect(Capabilities.android.canAdvertise, isTrue);
      expect(Capabilities.android.canRequestMtu, isTrue);
      expect(Capabilities.android.maxMtu, equals(517));
      // I035 Stage A: canBond temporarily false until the Dart-side
      // bonding methods are wired through Pigeon (Stage B).
      expect(Capabilities.android.canBond, isFalse);
      expect(Capabilities.android.canRequestEnable, isTrue);
    });

    test('iOS capabilities', () {
      expect(Capabilities.iOS.canAdvertise, isTrue);
      expect(Capabilities.iOS.maxMtu, equals(185));
      expect(Capabilities.iOS.canScanInBackground, isTrue);
      expect(Capabilities.iOS.canAdvertiseInBackground, isTrue);
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
}

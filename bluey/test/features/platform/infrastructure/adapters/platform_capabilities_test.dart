import 'package:bluey/src/features/platform/domain/capabilities.dart';
import 'package:bluey/src/features/platform/infrastructure/adapters/platform_capabilities.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capabilitiesFrom', () {
    final pairs = {
      'android': (platform.Capabilities.android, Capabilities.android),
      'iOS': (platform.Capabilities.iOS, Capabilities.iOS),
      'macOS': (platform.Capabilities.macOS, Capabilities.macOS),
      'windows': (platform.Capabilities.windows, Capabilities.windows),
      'linux': (platform.Capabilities.linux, Capabilities.linux),
      'fake': (platform.Capabilities.fake, Capabilities.fake),
    };
    for (final MapEntry(key: name, value: (theirs, ours)) in pairs.entries) {
      test('$name maps to the constant of the same name', () {
        expect(capabilitiesFrom(theirs), ours);
      });
    }

    final kinds = {
      platform.PlatformKind.android: PlatformKind.android,
      platform.PlatformKind.ios: PlatformKind.ios,
      platform.PlatformKind.fake: PlatformKind.fake,
      platform.PlatformKind.other: PlatformKind.other,
    };
    for (final MapEntry(key: theirs, value: ours) in kinds.entries) {
      test('the platform kind ${theirs.name} is carried', () {
        expect(
          capabilitiesFrom(
            platform.Capabilities(platformKind: theirs),
          ).platformKind,
          ours,
        );
      });
    }

    test('every flag is carried', () {
      // arrange
      const source = platform.Capabilities(
        platformKind: platform.PlatformKind.other,
        canScan: false,
        canConnect: false,
        canAdvertise: true,
        canRequestMtu: true,
        maxMtu: 185,
        canScanInBackground: true,
        canAdvertiseInBackground: true,
        canBond: true,
        canRequestPhy: true,
        canRequestConnectionParameters: true,
        canRequestEnable: true,
        canAdvertiseManufacturerData: true,
        reportsCentralDisconnects: true,
      );

      // act
      final ours = capabilitiesFrom(source);

      // assert
      expect(
        ours,
        const Capabilities(
          platformKind: PlatformKind.other,
          canScan: false,
          canConnect: false,
          canAdvertise: true,
          canRequestMtu: true,
          maxMtu: 185,
          canScanInBackground: true,
          canAdvertiseInBackground: true,
          canBond: true,
          canRequestPhy: true,
          canRequestConnectionParameters: true,
          canRequestEnable: true,
          canAdvertiseManufacturerData: true,
          reportsCentralDisconnects: true,
        ),
      );
    });
  });
}

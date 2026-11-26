import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_link_features.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carries the five facts from the flags of the platform', () {
    // arrange
    const source = platform.Capabilities(
      platformKind: platform.PlatformKind.android,
      canBond: true,
      canRequestPhy: false,
      canRequestConnectionParameters: true,
      canRequestMtu: true,
      maxMtu: 185,
    );

    // act
    final features = linkFeaturesFrom(source);

    // assert
    expect(
      features,
      const LinkFeatures(
        canBond: true,
        canRequestPhy: false,
        canRequestParameters: true,
        canRequestMtu: true,
        maxMtu: 185,
      ),
    );
  });

  test('reads each flag on its own', () {
    // arrange
    const source = platform.Capabilities(
      platformKind: platform.PlatformKind.ios,
      canBond: false,
      canRequestPhy: true,
      canRequestConnectionParameters: false,
      canRequestMtu: false,
      maxMtu: 23,
    );

    // act
    final features = linkFeaturesFrom(source);

    // assert
    expect(
      features,
      const LinkFeatures(
        canBond: false,
        canRequestPhy: true,
        canRequestParameters: false,
        canRequestMtu: false,
        maxMtu: 23,
      ),
    );
  });
}

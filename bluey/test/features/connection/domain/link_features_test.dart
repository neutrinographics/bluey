import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_features.dart';
import 'package:bluey/src/features/connection/domain/link_operation.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:flutter_test/flutter_test.dart';

const features = LinkFeatures(
  canBond: true,
  canRequestPhy: true,
  canRequestParameters: true,
  canRequestMtu: true,
  maxMtu: 247,
);

void main() {
  group('admit', () {
    test('admits an MTU up to the maximum', () {
      // act
      final answer = features.admit(Mtu(247));

      // assert
      expect(answer, Right<ConnectionFailure, Mtu>(Mtu(247)));
    });

    test('refuses an MTU above it', () {
      // act
      final answer = features.admit(Mtu(248));

      // assert
      expect(
        answer,
        Left<ConnectionFailure, Mtu>(
          MtuAboveMaximum(requested: Mtu(248), maximum: 247),
        ),
      );
    });

    test('refuses every MTU on a platform that cannot ask for one', () {
      // arrange
      const cannotAsk = LinkFeatures(
        canBond: true,
        canRequestPhy: true,
        canRequestParameters: true,
        canRequestMtu: false,
        maxMtu: 247,
      );

      // act
      final answer = cannotAsk.admit(Mtu.minimum);

      // assert
      expect(
        answer,
        const Left<ConnectionFailure, Mtu>(
          FeatureUnsupported(LinkOperation.negotiateMtu),
        ),
      );
    });
  });

  group('equality', () {
    test('is equal by value', () {
      // arrange
      const same = LinkFeatures(
        canBond: true,
        canRequestPhy: true,
        canRequestParameters: true,
        canRequestMtu: true,
        maxMtu: 247,
      );

      // act
      final equal = features == same;

      // assert
      expect(equal, isTrue);
      expect(features.hashCode, same.hashCode);
    });

    final others = <String, LinkFeatures>{
      'canBond': const LinkFeatures(
        canBond: false,
        canRequestPhy: true,
        canRequestParameters: true,
        canRequestMtu: true,
        maxMtu: 247,
      ),
      'canRequestPhy': const LinkFeatures(
        canBond: true,
        canRequestPhy: false,
        canRequestParameters: true,
        canRequestMtu: true,
        maxMtu: 247,
      ),
      'canRequestParameters': const LinkFeatures(
        canBond: true,
        canRequestPhy: true,
        canRequestParameters: false,
        canRequestMtu: true,
        maxMtu: 247,
      ),
      'canRequestMtu': const LinkFeatures(
        canBond: true,
        canRequestPhy: true,
        canRequestParameters: true,
        canRequestMtu: false,
        maxMtu: 247,
      ),
      'maxMtu': const LinkFeatures(
        canBond: true,
        canRequestPhy: true,
        canRequestParameters: true,
        canRequestMtu: true,
        maxMtu: 517,
      ),
    };

    for (final MapEntry(key: name, value: other) in others.entries) {
      test('differs from one of another $name', () {
        // act
        final equal = features == other;

        // assert
        expect(equal, isFalse);
      });
    }
  });
}

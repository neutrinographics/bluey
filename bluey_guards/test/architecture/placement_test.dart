import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('of', () {
    test('places a public library', () {
      // act
      final placement = Placement.of('lib/bluey.dart');

      // assert
      expect(placement, isA<PublicLibrary>());
    });

    test('places the edge', () {
      // act
      final placement = Placement.of('lib/src/api/connection/connection.dart');

      // assert
      expect(placement, isA<InApi>());
    });

    test('places a context file by context and layer', () {
      // act
      final placement = Placement.of(
        'lib/src/features/connection/domain/value_objects/mtu.dart',
      );

      // assert
      expect(
        placement,
        isA<InFeature>()
            .having((p) => p.context, 'context', 'connection')
            .having((p) => p.layer, 'layer', Layer.domain)
            .having((p) => p.isBridge, 'isBridge', isFalse),
      );
    });

    test('knows a bridge from an adapter', () {
      // act
      final bridge = Placement.of(
        'lib/src/features/peer/infrastructure/bridges/connection_peer_link.dart',
      );
      final adapter = Placement.of(
        'lib/src/features/peer/infrastructure/adapters/platform_peer_link.dart',
      );

      // assert
      expect(
        bridge,
        isA<InFeature>().having((p) => p.isBridge, 'isBridge', isTrue),
      );
      expect(
        adapter,
        isA<InFeature>().having((p) => p.isBridge, 'isBridge', isFalse),
      );
    });

    test('places the kernel by layer', () {
      // act
      final placement = Placement.of('lib/src/shared/domain/either.dart');

      // assert
      expect(
        placement,
        isA<InShared>().having((p) => p.layer, 'layer', Layer.domain),
      );
    });

    test(
      'leaves everything else under lib/src unplaced, with the folder it sits in',
      () {
        // arrange
        Matcher unplacedIn(String? folder) =>
            isA<Unplaced>().having((p) => p.folder, 'folder', folder);

        // act
        final legacy = Placement.of('lib/src/connection/bluey_connection.dart');
        final sharedRoot = Placement.of('lib/src/shared/exceptions.dart');
        final srcRoot = Placement.of('lib/src/bluey.dart');
        final featureRoot = Placement.of(
          'lib/src/features/connection/link.dart',
        );
        final unknownLayer = Placement.of(
          'lib/src/features/connection/presentation/page.dart',
        );

        // assert
        expect(legacy, unplacedIn('connection'));
        expect(sharedRoot, unplacedIn('shared'));
        expect(srcRoot, unplacedIn(null));
        expect(featureRoot, unplacedIn('features'));
        expect(unknownLayer, unplacedIn('features'));
      },
    );

    test('refuses a path outside lib', () {
      // act
      void place() => Placement.of('test/a_test.dart');

      // assert
      expect(place, throwsArgumentError);
    });
  });
}

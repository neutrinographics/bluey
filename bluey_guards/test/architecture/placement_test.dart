import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('of', () {
    test('places a public library', () {
      // arrange
      const path = 'lib/bluey.dart';

      // act
      final placement = Placement.of(path);

      // assert
      expect(placement, isA<PublicLibrary>());
    });

    test('places the edge', () {
      // arrange
      const path = 'lib/src/api/connection/connection.dart';

      // act
      final placement = Placement.of(path);

      // assert
      expect(placement, isA<InApi>());
    });

    test('places an edge file by the context its folder names', () {
      // arrange
      const path = 'lib/src/api/connection/x.dart';

      // act
      final placement = Placement.of(path);

      // assert
      expect(placement, const InApi(context: 'connection'));
    });

    test('places a file directly in the edge in no context', () {
      // arrange
      const path = 'lib/src/api/bluey.dart';

      // act
      final placement = Placement.of(path);

      // assert
      expect(placement, const InApi(context: null));
    });

    test('tells an edge file of a context from one directly in the edge', () {
      // act
      final inContext = Placement.of('lib/src/api/connection/x.dart');
      final direct = Placement.of('lib/src/api/bluey.dart');

      // assert
      expect(inContext, isNot(direct));
      expect(inContext.toString(), isNot(direct.toString()));
    });

    test('places a context file by context and layer', () {
      // arrange
      const path = 'lib/src/features/connection/domain/value_objects/mtu.dart';

      // act
      final placement = Placement.of(path);

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
      // arrange
      const bridgePath =
          'lib/src/features/peer/infrastructure/bridges/connection_peer_link.dart';
      const adapterPath =
          'lib/src/features/peer/infrastructure/adapters/platform_peer_link.dart';

      // act
      final bridge = Placement.of(bridgePath);
      final adapter = Placement.of(adapterPath);

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
      // arrange
      const path = 'lib/src/shared/domain/either.dart';

      // act
      final placement = Placement.of(path);

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
        const legacyPath = 'lib/src/connection/bluey_connection.dart';
        const sharedRootPath = 'lib/src/shared/exceptions.dart';
        const srcRootPath = 'lib/src/bluey.dart';
        const featureRootPath = 'lib/src/features/connection/link.dart';
        const unknownLayerPath =
            'lib/src/features/connection/presentation/page.dart';

        // act
        final legacy = Placement.of(legacyPath);
        final sharedRoot = Placement.of(sharedRootPath);
        final srcRoot = Placement.of(srcRootPath);
        final featureRoot = Placement.of(featureRootPath);
        final unknownLayer = Placement.of(unknownLayerPath);

        // assert
        expect(legacy, unplacedIn('connection'));
        expect(sharedRoot, unplacedIn('shared'));
        expect(srcRoot, unplacedIn(null));
        expect(featureRoot, unplacedIn('features'));
        expect(unknownLayer, unplacedIn('features'));
      },
    );

    test('refuses a path outside lib', () {
      // arrange
      const path = 'test/a_test.dart';

      // act
      void place() => Placement.of(path);

      // assert
      expect(place, throwsArgumentError);
    });
  });
}

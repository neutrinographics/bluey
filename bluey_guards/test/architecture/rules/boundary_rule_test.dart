import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

final _rule = BoundaryRule(
  package: 'bluey',
  legacy: const LegacyLayout(
    contexts: {'connection', 'discovery'},
    shared: {'shared', 'log'},
  ),
);

void main() {
  group("today's folders", () {
    test('a context that names another context is a violation', () {
      // arrange
      final files = tree({
        'lib/src/connection/a.dart': naming([
          '../discovery/b.dart',
          'package:bluey/src/discovery/c.dart',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/connection/a.dart -> lib/src/discovery/b.dart',
        'lib/src/connection/a.dart -> lib/src/discovery/c.dart',
      ]);
    });

    test('the kernel naming a context is a violation', () {
      // arrange
      final files = tree({
        'lib/src/log/logger.dart': naming(['../connection/a.dart']),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, ['lib/src/log/logger.dart -> lib/src/connection/a.dart']);
    });

    test(
      'a context may name itself, the kernel, a root file and other packages',
      () {
        // arrange
        final files = tree({
          'lib/src/connection/a.dart': naming([
            'b.dart',
            'value_objects/mtu.dart',
            '../shared/uuid.dart',
            '../log/log.dart',
            '../events.dart',
            'dart:async',
            'package:meta/meta.dart',
          ]),
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, isEmpty);
      },
    );

    test('a root file, the edge and a public library are never judged', () {
      // arrange
      final files = tree({
        'lib/bluey.dart':
            "export 'src/connection/a.dart';\nexport 'src/discovery/b.dart';",
        'lib/src/api/bluey.dart': naming([
          '../features/connection/application/connect_device.dart',
          '../discovery/b.dart',
        ]),
        'lib/src/bluey.dart': naming(['connection/a.dart', 'discovery/b.dart']),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, isEmpty);
    });
  });

  group('the target layout', () {
    test(
      'a context that names another context is a violation, placed or not',
      () {
        // arrange
        final files = tree({
          'lib/src/discovery/scanner.dart': naming([
            '../features/connection/domain/link.dart',
          ]),
          'lib/src/features/peer/application/watch_peer.dart': naming([
            '../../connection/domain/link.dart',
            '../../../discovery/device.dart',
          ]),
        });

        // act
        final found = entries(_rule, files);

        // assert
        expect(found, [
          'lib/src/discovery/scanner.dart -> '
              'lib/src/features/connection/domain/link.dart',
          'lib/src/features/peer/application/watch_peer.dart -> '
              'lib/src/features/connection/domain/link.dart',
          'lib/src/features/peer/application/watch_peer.dart -> '
              'lib/src/discovery/device.dart',
        ]);
      },
    );

    test("a bridge may name the other context's domain and application, "
        'not its infrastructure', () {
      // arrange
      const bridge =
          'lib/src/features/peer/infrastructure/bridges/'
          'connection_peer_link.dart';
      final files = tree({
        bridge: naming([
          '../../../connection/application/disconnect.dart',
          '../../../connection/domain/link.dart',
          '../../../connection/infrastructure/adapters/platform_links.dart',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        '$bridge -> '
            'lib/src/features/connection/infrastructure/adapters/'
            'platform_links.dart',
      ]);
    });

    test('an adapter is not a bridge', () {
      // arrange
      const adapter =
          'lib/src/features/peer/infrastructure/adapters/'
          'platform_peer_link.dart';
      final files = tree({
        adapter: naming(['../../../connection/application/disconnect.dart']),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        '$adapter -> lib/src/features/connection/application/disconnect.dart',
      ]);
    });

    test('the placed kernel naming a context is a violation', () {
      // arrange
      final files = tree({
        'lib/src/shared/domain/either.dart': naming([
          '../../features/connection/domain/link.dart',
        ]),
      });

      // act
      final found = entries(_rule, files);

      // assert
      expect(found, [
        'lib/src/shared/domain/either.dart -> '
            'lib/src/features/connection/domain/link.dart',
      ]);
    });
  });

  group('the debt an entry records', () {
    test("is its source's dependency on a context of today's folders", () {
      // act
      final debt = _rule.weigh(
        'lib/src/connection/a.dart -> lib/src/discovery/b.dart',
      );

      // assert
      expect(debt, (
        debt: 'lib/src/connection/a.dart into discovery',
        amount: 1,
      ));
    });

    test('is the same debt when its target moved into the target layout', () {
      // act
      final debt = _rule.weigh(
        'lib/src/connection/a.dart -> '
        'lib/src/features/discovery/domain/b.dart',
      );

      // assert
      expect(debt, (
        debt: 'lib/src/connection/a.dart into discovery',
        amount: 1,
      ));
    });

    test('is the entry itself, once, when it names no context', () {
      // act
      final debt = _rule.weigh('lib/src/connection/a.dart -> 420 lines');

      // assert
      expect(debt, (debt: 'lib/src/connection/a.dart -> 420 lines', amount: 1));
    });
  });

  group('a known entry and a found entry of one source and context', () {
    test('tells a target that moved to rewrite the entry', () {
      // arrange
      const known = 'lib/src/connection/a.dart -> lib/src/discovery/b.dart';
      const found =
          'lib/src/connection/a.dart -> '
          'lib/src/features/discovery/domain/b.dart';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(
        change,
        'lib/src/connection/a.dart still depends on discovery, but on '
        'lib/src/features/discovery/domain/b.dart, not on '
        'lib/src/discovery/b.dart: rewrite the entry to the new path',
      );
    });

    test('is no change when the two entries are into different contexts', () {
      // arrange
      const known = 'lib/src/connection/a.dart -> lib/src/discovery/b.dart';
      const found = 'lib/src/connection/a.dart -> lib/src/log/c.dart';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(change, isNull);
    });

    test('is no change when the two entries are of different sources', () {
      // arrange
      const known = 'lib/src/connection/a.dart -> lib/src/discovery/b.dart';
      const found = 'lib/src/connection/z.dart -> lib/src/discovery/b.dart';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(change, isNull);
    });

    test('is no change when an entry names no context', () {
      // arrange
      const known = 'lib/src/connection/a.dart -> 420 lines';
      const found = 'lib/src/connection/a.dart -> 410 lines';

      // act
      final change = _rule.change(known: known, found: found);

      // assert
      expect(change, isNull);
    });
  });
}

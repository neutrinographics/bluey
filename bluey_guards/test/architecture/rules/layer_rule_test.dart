import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

import '../support/trees.dart';

const _domain = 'lib/src/features/connection/domain/link.dart';
const _application =
    'lib/src/features/connection/application/connect_device.dart';
const _adapter =
    'lib/src/features/connection/infrastructure/adapters/platform_links.dart';
const _platform =
    'package:bluey_platform_interface/bluey_platform_interface.dart';
final _rule = LayerRule(
  package: 'bluey',
  allowances: const LayerAllowances(
    domain: {
      'dart:core',
      'dart:typed_data',
      'dart:collection',
      'dart:math',
      'package:meta',
    },
    application: {'dart:async', 'package:clock'},
    infrastructure: {
      'package:bluey_platform_interface',
      'package:flutter/services.dart',
    },
  ),
  compositionRoots: const {'lib/src/api/bluey.dart'},
);

List<String> found(Map<String, String> files) => entries(_rule, tree(files));

void main() {
  group('domain', () {
    test(
      "names its own domain, the kernel's domain and its allowed libraries",
      () {
        // act
        final violations = found({
          _domain: naming([
            'link_state.dart',
            '../../../shared/domain/either.dart',
            'dart:typed_data',
            'package:meta/meta.dart',
          ]),
        });

        // assert
        expect(violations, isEmpty);
      },
    );

    test('may not reach outward', () {
      // act
      final violations = found({
        _domain: naming([
          '../application/connect_device.dart',
          '../../../shared/application/log.dart',
          'dart:async',
          'package:clock/clock.dart',
        ]),
      });

      // assert
      expect(violations, [
        '$_domain -> lib/src/features/connection/application/'
            'connect_device.dart',
        '$_domain -> lib/src/shared/application/log.dart',
        '$_domain -> dart:async',
        '$_domain -> package:clock/clock.dart',
      ]);
    });
  });

  group('application', () {
    test('names what domain may, its own layer and its allowed libraries', () {
      // act
      final violations = found({
        _application: naming([
          '../domain/link.dart',
          'ports/links.dart',
          '../../../shared/application/log.dart',
          'dart:async',
          'dart:math',
          'package:clock/clock.dart',
        ]),
      });

      // assert
      expect(violations, isEmpty);
    });

    test('may not name infrastructure or a framework', () {
      // act
      final violations = found({
        _application: naming([
          '../infrastructure/adapters/platform_links.dart',
          '../../../shared/infrastructure/bluey_logger.dart',
          _platform,
        ]),
      });

      // assert
      expect(violations, [
        '$_application -> $_adapter',
        '$_application -> lib/src/shared/infrastructure/bluey_logger.dart',
        '$_application -> $_platform',
      ]);
    });
  });

  group('infrastructure', () {
    test(
      'names its whole context, the whole kernel and its two frameworks',
      () {
        // act
        final violations = found({
          _adapter: naming([
            '../../domain/link.dart',
            '../../application/ports/links.dart',
            '../../../../shared/infrastructure/platform_errors.dart',
            _platform,
            'package:flutter/services.dart',
          ]),
        });

        // assert
        expect(violations, isEmpty);
      },
    );

    test('may name no other part of Flutter', () {
      // act
      final violations = found({
        _adapter: naming(['package:flutter/widgets.dart']),
      });

      // assert
      expect(violations, ['$_adapter -> package:flutter/widgets.dart']);
    });
  });

  group('the kernel', () {
    test('keeps the same order of layers and names no edge', () {
      // arrange
      const either = 'lib/src/shared/domain/either.dart';

      // act
      final violations = found({
        either: naming([
          'failure.dart',
          '../application/log.dart',
          '../../api/exceptions.dart',
        ]),
      });

      // assert
      expect(violations, [
        '$either -> lib/src/shared/application/log.dart',
        '$either -> lib/src/api/exceptions.dart',
      ]);
    });
  });

  group('placed and unplaced code', () {
    test(
      'placed code names no unplaced code, no edge and no public library',
      () {
        // act
        final violations = found({
          _application: naming([
            '../../../connection/bluey_connection.dart',
            '../../../api/exceptions.dart',
            '../../../../bluey.dart',
          ]),
        });

        // assert
        expect(violations, [
          '$_application -> lib/src/connection/bluey_connection.dart',
          '$_application -> lib/src/api/exceptions.dart',
          '$_application -> lib/bluey.dart',
        ]);
      },
    );

    test(
      "another context is the boundary rule's to judge, and unplaced code is "
      'not judged',
      () {
        // act
        final violations = found({
          _domain: naming(['../../peer/domain/server_id.dart']),
          'lib/src/connection/a.dart': naming(['dart:io', '../bluey.dart']),
        });

        // assert
        expect(violations, isEmpty);
      },
    );
  });

  group('a public library', () {
    test("may not name a context's infrastructure", () {
      // act
      final violations = found({
        'lib/bluey.dart':
            "export 'src/features/x/infrastructure/adapters/a.dart';",
      });

      // assert
      expect(violations, [
        'lib/bluey.dart -> lib/src/features/x/infrastructure/adapters/a.dart',
      ]);
    });

    test(
      "may name a context's infrastructure when it is a composition root",
      () {
        // arrange
        final rule = LayerRule(
          package: 'bluey',
          allowances: const LayerAllowances(
            domain: {},
            application: {},
            infrastructure: {},
          ),
          compositionRoots: const {'lib/bluey.dart'},
        );
        final files = tree({
          'lib/bluey.dart':
              "export 'src/features/x/infrastructure/adapters/a.dart';",
        });

        // act
        final violations = entries(rule, files);

        // assert
        expect(violations, isEmpty);
      },
    );
  });

  group('the edge', () {
    test("names any context's domain and application, and unplaced code", () {
      // act
      final violations = found({
        'lib/src/api/connection/connection.dart': naming([
          '../../features/connection/domain/link.dart',
          '../../features/peer/application/watch_peer.dart',
          '../../connection/bluey_connection.dart',
          '../exceptions.dart',
          'dart:async',
        ]),
      });

      // assert
      expect(violations, isEmpty);
    });

    test('only the composition root names an infrastructure folder', () {
      // act
      final violations = found({
        'lib/src/api/bluey.dart': naming([
          '../features/connection/infrastructure/adapters/platform_links.dart',
        ]),
        'lib/src/api/connection/connection.dart': naming([
          '../../features/connection/infrastructure/adapters/'
              'platform_links.dart',
        ]),
      });

      // assert
      expect(violations, [
        'lib/src/api/connection/connection.dart -> $_adapter',
      ]);
    });
  });
}

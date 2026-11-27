import 'dart:io';

import 'package:bluey_guards/architecture.dart';
import 'package:bluey_guards/gates.dart';

const _package = 'bluey';
const _compositionRoot = 'lib/src/api/bluey.dart';

/// The files that assemble the package and so may name every context's edge
/// and code: the one composition root and today's `lib/src/bluey.dart`, which
/// becomes it.
const _compositionRoots = {'lib/src/bluey.dart', _compositionRoot};

/// The six bounded contexts, each a folder under `lib/src/features/` in the
/// target layout and, until it moves, under `lib/src/` today.
const _contexts = {
  'connection',
  'discovery',
  'gatt_client',
  'gatt_server',
  'peer',
  'platform',
};

/// The package's library files and options files, read from the package root
/// a test runs in, so every rule judges the same snapshot.
SourceTree readBluey() => SourceTree.read(
  Directory.current,
  under: const ['lib'],
  extensions: const {'.dart', '.yaml'},
);

/// What Bluey's rules are known to find today, read from the list file
/// itself, so a rule is held to exactly the list the file declares and the
/// list gate compares the same text.
Map<String, List<String>> readKnownViolations() => readLists(
  File('test/architecture/known_violations.dart').readAsStringSync(),
);

/// Each rule Bluey is held to, by the name of the list of what it is known
/// to find today, so the architecture test judges one against the other.
final Map<String, ArchitectureRule> blueyRules = {
  'unplaced': const PlacementRule(contexts: _contexts),
  'boundaries': BoundaryRule(
    package: _package,
    legacy: const LegacyLayout(contexts: _contexts, shared: {'shared', 'log'}),
  ),
  'frameworkPlacement': FrameworkRule(
    package: _package,
    frameworks: const {'package:flutter', 'package:bluey_platform_interface'},
    compositionRoots: const {_compositionRoot},
  ),
  'publicExports': PublicExportsRule(package: _package),
  'reservedLibraries': const ReservedLibraryRule(
    libraries: {
      'package:bluey_platform_interface/platform_implementation.dart',
      'package:bluey_platform_interface/src/implementation/',
    },
  ),
  'layers': LayerRule(
    package: _package,
    allowances: const LayerAllowances(
      domain: {
        'dart:core',
        'dart:typed_data',
        'dart:collection',
        'dart:math',
        'package:meta',
      },
      application: {'dart:async'},
      infrastructure: {
        'package:bluey_platform_interface',
        'package:flutter/services.dart',
      },
    ),
    compositionRoots: const {_compositionRoot},
  ),
  'throws': ThrowsRule(
    programmingErrors: const {
      'StateError',
      'ArgumentError',
      'UnimplementedError',
    },
  ),
  'lintOptions': LintOptionsRule(
    roots: const [
      'lib/src/api',
      'lib/src/features',
      'lib/src/shared/domain',
      'lib/src/shared/application',
      'lib/src/shared/infrastructure',
    ],
    lints: const {'unawaited_futures', 'discarded_futures'},
  ),
  'oversized': SizeRule(limit: 300, extension: '.dart'),
  'edgeContexts': EdgeContextRule(
    package: _package,
    compositionRoots: _compositionRoots,
  ),
  'edgeFromBelow': EdgeFromBelowRule(
    package: _package,
    compositionRoots: _compositionRoots,
  ),
};

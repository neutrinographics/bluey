import 'dart:io';

import 'package:bluey_guards/architecture.dart';

import 'known_violations.dart';

const _package = 'bluey';
const _compositionRoot = 'lib/src/api/bluey.dart';

/// The package's library files and options files, read from the package root
/// a test runs in, so every rule judges the same snapshot.
SourceTree readBluey() => SourceTree.read(
  Directory.current,
  under: const ['lib'],
  extensions: const {'.dart', '.yaml'},
);

/// Each rule Bluey is held to, with the list of what it is known to find
/// today, so the architecture test judges one against the other.
final Map<ArchitectureRule, List<String>> rulesAndKnownViolations = {
  PlacementRule(): unplaced,
  BoundaryRule(
        package: _package,
        legacy: const LegacyLayout(
          contexts: {
            'connection',
            'discovery',
            'gatt_client',
            'gatt_server',
            'peer',
            'platform',
          },
          shared: {'shared', 'log'},
        ),
      ):
      boundaries,
  FrameworkRule(
    package: _package,
    frameworks: const {'package:flutter', 'package:bluey_platform_interface'},
    compositionRoots: const {_compositionRoot},
  ): frameworkPlacement,
  PublicExportsRule(package: _package): publicExports,
  LayerRule(
        package: _package,
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
        compositionRoots: const {_compositionRoot},
      ):
      layers,
  ThrowsRule(
        programmingErrors: const {
          'StateError',
          'ArgumentError',
          'UnimplementedError',
        },
      ):
      throws,
  LintOptionsRule(
        roots: const [
          'lib/src/api',
          'lib/src/features',
          'lib/src/shared/domain',
          'lib/src/shared/application',
          'lib/src/shared/infrastructure',
        ],
        lints: const {'unawaited_futures', 'discarded_futures'},
      ):
      lintOptions,
  SizeRule(limit: 300, extension: '.dart'): oversized,
};

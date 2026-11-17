import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_source.dart';
import 'source_file.dart';

/// The files of one package that the rules judge, read once, so every rule is
/// a pure function of the same snapshot.
final class SourceTree {
  /// A tree of [files], kept sorted by path so every answer a rule gives
  /// comes in one stable order.
  SourceTree(Iterable<SourceFile> files)
    : files = List.unmodifiable(
        [...files]..sort((a, b) => a.path.compareTo(b.path)),
      );

  /// Reads the files with one of [extensions] in the folders [under] of
  /// [packageRoot], leaving out the ones [isGenerated] names. A folder the
  /// package does not have is skipped, so one configuration serves packages
  /// with and without native sources. This is the only place a rule's input
  /// touches the disk.
  factory SourceTree.read(
    Directory packageRoot, {
    required List<String> under,
    required Set<String> extensions,
    bool Function(String path) isGenerated = isGeneratedSource,
  }) {
    final byPath = <String, SourceFile>{};
    for (final folder in under) {
      final directory = Directory(p.join(packageRoot.path, folder));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = _packageRelative(entity, packageRoot);
        if (!extensions.contains(p.posix.extension(path))) continue;
        if (isGenerated(path)) continue;
        byPath[path] = SourceFile(
          path: path,
          content: entity.readAsStringSync(),
        );
      }
    }
    return SourceTree(byPath.values);
  }

  /// Every file of the tree, sorted by path.
  final List<SourceFile> files;

  late final Map<String, SourceFile> _byPath = {
    for (final file in files) file.path: file,
  };

  /// The files whose extension is exactly [extension], for a rule that judges
  /// one language.
  Iterable<SourceFile> withExtension(String extension) =>
      files.where((file) => file.hasExtension(extension));

  /// The file at [path], or null when the tree does not hold it.
  SourceFile? file(String path) => _byPath[path];

  /// Every Dart file of the tree, parsed once however many rules ask.
  late final List<DartSource> dartSources = List.unmodifiable(
    withExtension('.dart').map(DartSource.parse),
  );
}

String _packageRelative(File file, Directory packageRoot) =>
    p.split(p.relative(file.path, from: packageRoot.path)).join('/');

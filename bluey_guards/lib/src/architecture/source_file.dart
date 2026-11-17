import 'package:path/path.dart' as p;

/// One file of a package as a rule sees it, so a rule judges text it was
/// handed and never reads the disk itself.
final class SourceFile {
  /// A file at [path] holding [content]; tests build one in memory.
  const SourceFile({required this.path, required this.content});

  /// Where the file sits in its package, relative to the package root and
  /// with forward slashes, so a list entry reads the same on every machine.
  final String path;

  /// The file's text.
  final String content;

  /// How many lines of text the file holds, a last line with no line break
  /// counted and a Windows line break counted once, so a size limit means the
  /// same on every platform.
  int get lineCount {
    if (content.isEmpty) return 0;
    final breaks = '\n'.allMatches(content).length;
    return content.endsWith('\n') ? breaks : breaks + 1;
  }

  /// Whether the file's extension is exactly [extension] (such as `.dart`),
  /// so `.art` never matches a Dart file.
  bool hasExtension(String extension) => p.posix.extension(path) == extension;

  @override
  String toString() => 'SourceFile($path)';
}

/// Whether [path] names a generated file, one with `.g.` before its extension
/// (Pigeon's `messages.g.dart`, `Messages.g.kt`, `Messages.g.swift`), which no
/// rule should judge since nobody writes it by hand.
bool isGeneratedSource(String path) =>
    p.posix.basenameWithoutExtension(path).endsWith('.g');

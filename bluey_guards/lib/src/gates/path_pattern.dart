/// A folder of a package, written as a path whose `*` stands for any one
/// folder (`lib/src/features/*/domain`), so a gate can hold every context's
/// domain to one floor without naming the contexts.
final class PathPattern {
  /// The pattern [pattern], with forward slashes.
  PathPattern(this.pattern);

  /// The pattern as written.
  final String pattern;

  /// Whether [path], relative and with forward slashes, lies under the folder
  /// the pattern names. A path that only begins with the same text
  /// (`domains/` for `domain`) is not under it.
  bool takesIn(String path) {
    final folders = pattern.split('/');
    final segments = path.split('/');
    if (segments.length <= folders.length) return false;
    for (var i = 0; i < folders.length; i++) {
      if (folders[i] != '*' && folders[i] != segments[i]) return false;
    }
    return true;
  }

  @override
  String toString() => pattern;
}

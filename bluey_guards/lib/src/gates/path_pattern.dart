/// A folder of a package, written as a path whose `*` stands for any one
/// folder (`lib/src/features/*/domain`), so a gate can hold every context's
/// domain to one floor without naming the contexts.
final class PathPattern {
  /// The pattern [written], with forward slashes. A trailing slash is
  /// dropped, since `lib/src/shared/domain/` names the same folder and would
  /// otherwise take in nothing, leaving a floor that silently holds nothing.
  PathPattern(String written) : pattern = _withoutTrailingSlashes(written);

  /// The pattern, without a trailing slash.
  final String pattern;

  static String _withoutTrailingSlashes(String written) {
    var pattern = written;
    while (pattern.length > 1 && pattern.endsWith('/')) {
      pattern = pattern.substring(0, pattern.length - 1);
    }
    return pattern;
  }

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

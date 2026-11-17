import 'package:path/path.dart' as p;

/// What a URI a file names points at, a file of the same package or a
/// library outside it, so a rule compares paths and never parses a URI.
sealed class Dependency {
  const Dependency._();

  /// Resolves [uri], named by the file at [from] of [package]: a relative URI
  /// against [from]'s folder, a `package:` URI of [package] to its file under
  /// `lib/`, and anything else to an [External].
  factory Dependency.resolve({
    required String from,
    required String uri,
    required String package,
  }) {
    final ownPrefix = 'package:$package/';
    if (uri.startsWith(ownPrefix)) {
      return Internal(path: 'lib/${uri.substring(ownPrefix.length)}');
    }
    if (Uri.parse(uri).hasScheme) return External(uri: uri);
    return Internal(
      path: p.posix.normalize(p.posix.join(p.posix.dirname(from), uri)),
    );
  }
}

/// A file of the same package, by its package-relative path.
final class Internal extends Dependency {
  /// The file at [path].
  const Internal({required this.path}) : super._();

  /// The package-relative path of the file depended on.
  final String path;

  @override
  bool operator ==(Object other) => other is Internal && other.path == path;

  @override
  int get hashCode => Object.hash(Internal, path);

  @override
  String toString() => 'Internal($path)';
}

/// A library outside the package: another package or the SDK.
final class External extends Dependency {
  /// The library [uri] names.
  const External({required this.uri}) : super._();

  /// The URI as the file names it.
  final String uri;

  /// Whether this library is [library] itself or one of its package's
  /// libraries when [library] names a whole package (`package:flutter` holds
  /// `package:flutter/services.dart`), never a package whose name merely
  /// begins the same way.
  bool isWithin(String library) =>
      uri == library || uri.startsWith('$library/');

  @override
  bool operator ==(Object other) => other is External && other.uri == uri;

  @override
  int get hashCode => Object.hash(External, uri);

  @override
  String toString() => 'External($uri)';
}

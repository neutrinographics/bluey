/// The three layers a context or the kernel is cut into, inner to outer, so a
/// rule can say which way a dependency may point.
enum Layer { domain, application, infrastructure }

/// Where a path under `lib/` sits in the target layout, so a rule judges a
/// file by its place and never parses a path itself.
sealed class Placement {
  const Placement._();

  /// Places [path], a package-relative path under `lib/`. Throws an
  /// [ArgumentError] for any other path, since only a library file has a
  /// place in the layout.
  factory Placement.of(String path) {
    final segments = path.split('/');
    if (segments.length < 2 || segments.first != 'lib') {
      throw ArgumentError.value(path, 'path', 'is not under lib/');
    }
    final inLib = segments.sublist(1);
    if (inLib.length == 1) return const PublicLibrary();
    if (inLib.first != 'src') return const Unplaced(folder: null);
    return _placeInSrc(inLib.sublist(1));
  }
}

/// A public library, `lib/<name>.dart`: what a consumer imports.
final class PublicLibrary extends Placement {
  /// The one placement every public library shares.
  const PublicLibrary() : super._();

  @override
  bool operator ==(Object other) => other is PublicLibrary;

  @override
  int get hashCode => (PublicLibrary).hashCode;

  @override
  String toString() => 'PublicLibrary';
}

/// The edge, `lib/src/api/**`: the public types, which may reach any layer.
final class InApi extends Placement {
  /// An edge file of [context], or of none for a file directly in `api/`.
  const InApi({this.context}) : super._();

  /// The first folder under `lib/src/api/`, the context whose public interface
  /// the file is, so a rule can hold the file to that context; null for a
  /// file directly in `api/`, which is the edge of no one context.
  final String? context;

  @override
  bool operator ==(Object other) => other is InApi && other.context == context;

  @override
  int get hashCode => Object.hash(InApi, context);

  @override
  String toString() => 'InApi(${context ?? 'api'})';
}

/// The shared kernel, `lib/src/shared/<layer>/**`, which names no context.
final class InShared extends Placement {
  /// A kernel file in [layer].
  const InShared({required this.layer}) : super._();

  /// The layer the file is in.
  final Layer layer;

  @override
  bool operator ==(Object other) => other is InShared && other.layer == layer;

  @override
  int get hashCode => Object.hash(InShared, layer);

  @override
  String toString() => 'InShared(${layer.name})';
}

/// A bounded context's file, `lib/src/features/<context>/<layer>/**`.
final class InFeature extends Placement {
  /// A file of [context] in [layer], a bridge when [isBridge].
  const InFeature({
    required this.context,
    required this.layer,
    this.isBridge = false,
  }) : super._();

  /// The bounded context the file belongs to.
  final String context;

  /// The layer the file is in.
  final Layer layer;

  /// Whether the file sits under `infrastructure/bridges/`, the one place a
  /// context may name another context.
  final bool isBridge;

  @override
  bool operator ==(Object other) =>
      other is InFeature &&
      other.context == context &&
      other.layer == layer &&
      other.isBridge == isBridge;

  @override
  int get hashCode => Object.hash(InFeature, context, layer, isBridge);

  @override
  String toString() =>
      'InFeature($context, ${layer.name}${isBridge ? ', bridge' : ''})';
}

/// A library file outside the target layout, today's code that has not moved
/// yet.
final class Unplaced extends Placement {
  /// A file in [folder].
  const Unplaced({required this.folder}) : super._();

  /// The first folder under `lib/src` the file sits in, so a rule can tell
  /// which of today's folders it came from; null for a file directly in
  /// `lib/src` or outside it.
  final String? folder;

  @override
  bool operator ==(Object other) => other is Unplaced && other.folder == folder;

  @override
  int get hashCode => Object.hash(Unplaced, folder);

  @override
  String toString() => 'Unplaced(${folder ?? 'lib/src'})';
}

Placement _placeInSrc(List<String> segments) {
  if (segments.length == 1) return const Unplaced(folder: null);
  final folder = segments.first;
  switch (folder) {
    case 'api':
      return InApi(context: segments.length > 2 ? segments[1] : null);
    case 'shared' when segments.length > 2:
      final layer = _layerNamed(segments[1]);
      if (layer != null) return InShared(layer: layer);
    case 'features' when segments.length > 3:
      final layer = _layerNamed(segments[2]);
      if (layer != null) {
        return InFeature(
          context: segments[1],
          layer: layer,
          isBridge:
              layer == Layer.infrastructure &&
              segments.length > 4 &&
              segments[3] == 'bridges',
        );
      }
  }
  return Unplaced(folder: folder);
}

Layer? _layerNamed(String name) {
  for (final layer in Layer.values) {
    if (layer.name == name) return layer;
  }
  return null;
}

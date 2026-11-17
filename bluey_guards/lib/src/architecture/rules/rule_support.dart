import '../dependency.dart';
import '../placement.dart';

/// The placement of [path], or null for a file outside `lib/`, so a rule
/// never asks [Placement.of] about a test or a tool.
Placement? libraryPlacement(String path) =>
    path.startsWith('lib/') ? Placement.of(path) : null;

/// The layer [placement] is in, or null for one that has no layer: the edge,
/// a public library or unplaced code.
Layer? layerOf(Placement placement) => switch (placement) {
  InFeature(:final layer) || InShared(:final layer) => layer,
  _ => null,
};

/// The placement of the file [dependency] points at, or null when it is a
/// library outside the package or a file outside `lib/`.
Placement? targetPlacement(Dependency dependency) => switch (dependency) {
  Internal(:final path) => libraryPlacement(path),
  External() => null,
};

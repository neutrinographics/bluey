/// What the architecture rules are known to find in this package today.
///
/// A list only shrinks. An entry leaves in the commit that fixes it, and a
/// size entry is rewritten with the lower count when its file shrinks. Nothing
/// is ever added, and no count is ever raised: fix the code instead.
/// docs/ARCHITECTURE.md says how to read a failure.
library;

/// The Dart files longer than 300 lines.
const oversizedDart = <String>[
  'lib/src/exceptions.dart -> 358 lines',
  'lib/src/platform_interface.dart -> 854 lines',
];

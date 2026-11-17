/// What the architecture rules are known to find in this package today.
///
/// A list only shrinks. An entry leaves in the commit that fixes it. An entry
/// is rewritten only for a debt that stayed or shrank: a size entry with the
/// lower count when its file shrinks, a boundaries entry with the new path
/// when its target moved within its context. No other entry is ever added,
/// and no count is ever raised: fix the code instead. docs/ARCHITECTURE.md
/// says how to read a failure.
library;

/// The Dart files longer than 300 lines.
const oversized = <String>[];

/// The public libraries' exports of anything but the package's own sources.
const publicExports = <String>[];

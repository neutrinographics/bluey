/// The known defects this package's run must find, each by its full test
/// name, group and test together, so a known defect cannot be deleted or
/// added without this list saying so.
///
/// A roster only shrinks. A name leaves in the commit that fixes its defect
/// and moves its test into the normal suite; nothing is ever added.
/// docs/ARCHITECTURE.md says how the Known defects job reads it.
library;

/// The full names of the known defects, in the order the run meets them.
const knownDefects = <String>[
  'M3 (I369): a second connect() to a connected device does not orphan the first connection\'s state stream',
  'M2 (I013): a rejected startScan surfaces on the scan stream, not as an unhandled async error',
];

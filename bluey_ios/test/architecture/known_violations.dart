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
const oversizedDart = <String>[
  'lib/src/bluey_ios.dart -> 676 lines',
  'lib/src/ios_connection_manager.dart -> 415 lines',
  'lib/src/ios_server.dart -> 429 lines',
];

/// The Swift files longer than 400 lines.
const oversizedSwift = <String>[
  'ios/Classes/CentralManagerImpl.swift -> 1005 lines',
  'ios/Classes/PeripheralManagerImpl.swift -> 671 lines',
];

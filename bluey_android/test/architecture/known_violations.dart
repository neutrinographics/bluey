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
  'lib/src/android_connection_manager.dart -> 408 lines',
  'lib/src/android_server.dart -> 407 lines',
  'lib/src/bluey_android.dart -> 703 lines',
];

/// The Kotlin files longer than 400 lines.
const oversizedKotlin = <String>[
  'android/src/main/kotlin/com/neutrinographics/bluey/BlueyPlugin.kt -> 785 lines',
  'android/src/main/kotlin/com/neutrinographics/bluey/ConnectionManager.kt -> 1092 lines',
  'android/src/main/kotlin/com/neutrinographics/bluey/GattServer.kt -> 1260 lines',
];

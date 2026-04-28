/// Platform interface for Bluey
///
/// Defines the contract that platform-specific implementations must follow.
/// This follows the Clean Architecture pattern where platform code is
/// an implementation detail that can be swapped.
library bluey_platform_interface;

export 'src/capabilities.dart';
export 'src/exceptions.dart';
export 'src/platform_interface.dart';
export 'src/platform_log_event.dart';

/// Code the platform packages share, so a rule they all keep is written once.
///
/// For `bluey_android` and `bluey_ios` alone: an app, and `bluey` itself,
/// speak only the platform interface, which this library is not part of.
library platform_implementation;

export 'src/implementation/device_streams.dart';

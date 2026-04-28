/// iOS-specific [Connection] extensions.
///
/// Reserved for future iOS-specific features (e.g., L2CAP channels,
/// state restoration). Currently empty — iOS exposes no central-side
/// extensions equivalent to Android's bonding/PHY/connection-parameter
/// APIs.
///
/// Access via `Connection.ios` with the null-aware operator. Returns
/// `null` on non-iOS platforms.
abstract class IosConnectionExtensions {
  // Reserved.
}

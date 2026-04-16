import 'package:bluey/bluey.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and retrieves the last-connected peer's [ServerId] using
/// [SharedPreferences].
class PeerStorage {
  static const _key = 'bluey_saved_peer_id';

  /// Loads the previously saved [ServerId], or `null` if none exists
  /// (or the stored value is corrupted).
  Future<ServerId?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == null) return null;
    try {
      return ServerId(stored);
    } catch (_) {
      return null;
    }
  }

  /// Persists [id] so it can be restored on next launch.
  Future<void> save(ServerId id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id.value);
  }

  /// Clears the saved peer identity.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

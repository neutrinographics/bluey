import 'package:bluey/bluey.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and retrieves the server's stable [ServerId] using
/// [SharedPreferences].
///
/// On first launch [loadOrGenerate] creates a fresh identity and stores
/// it. Subsequent calls return the same identity. [reset] clears the
/// stored value and generates a new one.
class ServerIdentityStorage {
  static const _key = 'bluey_server_id';

  /// Loads a previously stored [ServerId], or generates and persists a
  /// new one if none exists (or the stored value is corrupted).
  Future<ServerId> loadOrGenerate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored != null) {
      try {
        return ServerId(stored);
      } catch (_) {
        // corrupted value -- fall through to regenerate
      }
    }
    final fresh = ServerId.generate();
    await prefs.setString(_key, fresh.value);
    return fresh;
  }

  /// Clears the stored identity and generates a fresh replacement.
  Future<ServerId> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    final fresh = ServerId.generate();
    await prefs.setString(_key, fresh.value);
    return fresh;
  }
}

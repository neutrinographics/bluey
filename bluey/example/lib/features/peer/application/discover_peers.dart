import 'package:bluey/bluey.dart';

/// Use case for discovering nearby Bluey servers.
class DiscoverPeers {
  final Bluey _bluey;

  DiscoverPeers(this._bluey);

  /// Scans for Bluey servers and returns a list of discovered peers.
  Future<List<BlueyPeer>> call({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _bluey.discoverPeers(timeout: timeout);
  }
}

import '../../features/connection/application/link_session.dart';
import '../../features/connection/domain/link_id.dart';
import 'connection.dart';

/// One public Connection per link, so a second connect() returns the object
/// the app already has.
///
/// It keys by session, never by link id, since a later link to the same
/// device may carry the same id. Both lookups are weak: a Connection the app
/// has dropped is not kept alive here.
final class Connections {
  /// Builds over [present], which assembles the Connection a session shows
  /// the app; the composition root hands it in, since what a Connection is
  /// built from is infrastructure the edge may not name.
  Connections({required Connection Function(LinkSession session) present})
    : _present = present;

  final Connection Function(LinkSession session) _present;
  final Expando<Connection> _connections = Expando();
  final Expando<LinkId> _linkIds = Expando();

  /// The Connection of [session]: the same object every time for one
  /// session, presented on the first ask.
  Connection of(LinkSession session) =>
      _connections[session] ??= _presented(session);

  /// The link id behind a Connection this made, whether or not its link has
  /// ended; null for one it did not make.
  ///
  /// An ended link's id may already name the link that came after it, so a
  /// caller must not address the platform with it once the link has ended.
  LinkId? linkIdOf(Connection connection) => _linkIds[connection];

  Connection _presented(LinkSession session) {
    final connection = _present(session);
    _linkIds[connection] = session.link.id;
    return connection;
  }
}

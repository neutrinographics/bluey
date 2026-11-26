import 'package:bluey/src/api/connection/connection.dart';
import 'package:bluey/src/features/connection/application/link_session.dart';

/// A Connection standing for whatever the composition root presents over
/// [session], for tests that only ask which object they were handed; any
/// member it is asked for fails the test.
final class StubConnection implements Connection {
  StubConnection(this.session);

  /// The session it was presented for.
  final LinkSession session;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

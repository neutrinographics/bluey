import '../../features/connection/domain/link_end.dart';
import '../../features/connection/domain/link_phase.dart';
import 'connection_state.dart';

/// The state an app reads for a link in [phase], so the lifecycle can grow
/// words of its own while every app keeps reading the states it always has.
///
/// An outage is told apart from every other end, since it leaves the
/// connection stale rather than closed: the app must build a new one once
/// the radio is back.
ConnectionState connectionStateOf(LinkPhase phase) => switch (phase) {
  Linked() => ConnectionState.linked,
  Ready() => ConnectionState.ready,
  Closing() => ConnectionState.disconnecting,
  Ended(end: EndedByRadioOutage()) => ConnectionState.invalidated,
  Ended() => ConnectionState.disconnected,
};

/// The words of Connection's log lines that an app can read, in one place.
///
/// They are the words logs had before the lifecycle had words of its own,
/// kept so an app's log filters hold. The change that revises the log
/// wording deletes this file.
library;

import '../domain/link_end.dart';
import '../domain/link_phase.dart';

/// The context every line of Connection's lifecycle is logged under.
const connectionLogContext = 'bluey.connection';

/// The word a `state transition` line names for a link entering [phase].
String stateWordOf(LinkPhase phase) => switch (phase) {
  Linked() => 'ConnectionState.linked',
  Ready() => 'ConnectionState.ready',
  Closing() => 'ConnectionState.disconnecting',
  Ended(end: EndedByRadioOutage()) => 'ConnectionState.invalidated',
  Ended() => 'ConnectionState.disconnected',
};

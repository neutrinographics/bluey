import 'link_end.dart';

/// What the radio says about a link's connection, as a link reads it.
enum LinkReport { connecting, connected, disconnecting, disconnected }

/// Everything that can happen to a link. The set is closed, so a `Link`
/// that answers each of them answers every event a link can meet.
sealed class LinkInput {
  const LinkInput();
}

/// The link's services were discovered, so GATT operations are now safe.
final class ServicesDiscovered extends LinkInput {
  const ServicesDiscovered();
}

/// The radio reported the link's connection state.
final class RadioReported extends LinkInput {
  const RadioReported(this.report);

  /// What the radio reported.
  final LinkReport report;
}

/// The radio's reports for the link stopped, which can only mean the link is
/// gone.
final class ReportsEnded extends LinkInput {
  const ReportsEnded();
}

/// Someone asked for the link to be closed.
final class DisconnectRequested extends LinkInput {
  const DisconnectRequested();
}

/// The platform confirmed the close that was asked for.
final class CloseConfirmed extends LinkInput {
  const CloseConfirmed();
}

/// The platform failed the close that was asked for, so the link stays as it
/// was before the request.
final class CloseFailed extends LinkInput {
  const CloseFailed();
}

/// The radio became unusable.
final class RadioOutageBegan extends LinkInput {
  const RadioOutageBegan(this.outage);

  /// What made the radio unusable.
  final RadioOutage outage;
}

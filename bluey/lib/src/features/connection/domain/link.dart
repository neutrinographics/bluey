import 'package:meta/meta.dart';

import '../../../shared/domain/device_address.dart';
import 'link_end.dart';
import 'link_event.dart';
import 'link_id.dart';
import 'link_input.dart';
import 'link_phase.dart';

/// What the owner of a link must now do because of a step, which the link
/// cannot do itself: it touches no radio and holds nothing to release.
@immutable
sealed class LinkDuty {
  const LinkDuty();
}

/// Ask the platform to close the link, and feed its answer back.
final class CloseTheLink extends LinkDuty {
  const CloseTheLink();

  @override
  bool operator ==(Object other) => other is CloseTheLink;

  @override
  int get hashCode => (CloseTheLink).hashCode;
}

/// The link has ended: release what lives as long as it. It carries the
/// end, so a release can never be due on a link that has not ended.
final class ReleaseTheLink extends LinkDuty {
  const ReleaseTheLink(this.end);

  /// Why the link ended.
  final LinkEnd end;

  @override
  bool operator ==(Object other) => other is ReleaseTheLink && other.end == end;

  @override
  int get hashCode => Object.hash(ReleaseTheLink, end);
}

/// The answer to one input: the link as it now stands, the duty, if any,
/// that the input left its owner, the phase it entered, if any, and what it
/// raised for others to hear of.
final class LinkStep {
  const LinkStep(this.link, {this.duty, this.entered, this.events = const []});

  /// The link after the input.
  final Link link;

  /// What the owner must now do, or null when nothing is due.
  final LinkDuty? duty;

  /// The phase the step entered, or null when the link stayed in the same
  /// kind of phase, so an owner tells others of a move only when there was
  /// one: a closing link whose closer changed has not begun closing again.
  final LinkPhase? entered;

  /// What the step raised, in order; empty unless it opened or ended the
  /// link, so each is raised once in the link's life.
  final List<LinkEvent> events;
}

/// One link to a device and its lifecycle, which decides what every event
/// does to the link.
///
/// It is a value: [on] answers the next link and leaves this one as it was,
/// so one owner can keep the only current copy. An ended link is final, so a
/// late or repeated event can never revive it or change why it ended.
///
/// A closing report that arrives while a close of ours is in flight is the
/// platform echoing that request, so a failed close still returns the link
/// to where it was. A link the radio was closing on its own stays closing
/// when a close of ours fails, with no close in flight; the radio finishing
/// its close ends it, and a new [DisconnectRequested] asks for the close
/// again.
@immutable
final class Link {
  /// A link the platform has just connected at [at]; the lifecycle starts
  /// at [Linked]. It is the only way to build a link, so every link has
  /// walked the lifecycle from its start and was told of as opened.
  static LinkStep open({
    required LinkId id,
    required DeviceAddress device,
    required DateTime at,
  }) {
    const linked = Linked();
    return LinkStep(
      Link._(id: id, device: device, phase: linked),
      entered: linked,
      events: [LinkOpened(device: device, at: at)],
    );
  }

  const Link._({required this.id, required this.device, required this.phase});

  /// Which link this is.
  final LinkId id;

  /// The device the link reaches.
  final DeviceAddress device;

  /// Where the link stands in its lifecycle.
  final LinkPhase phase;

  /// Why the link ended; non-null exactly when it has.
  LinkEnd? get end => switch (phase) {
    Ended(:final end) => end,
    _ => null,
  };

  /// The end the link has reached, or the one a closing link is heading for;
  /// null while the link is up.
  LinkEnd? get endInSight => switch (phase) {
    UpPhase() => null,
    Closing(:final by) => _endOfClosingBy(by),
    Ended(:final end) => end,
  };

  /// Whether the link is up, linked or ready.
  bool get isUp => phase is UpPhase;

  /// Whether the link is being closed.
  bool get isClosing => phase is Closing;

  /// Whether the link has ended, for good.
  bool get hasEnded => phase is Ended;

  /// Answers what [input], which came at [at], does to this link.
  LinkStep on(LinkInput input, {required DateTime at}) => switch ((
    phase,
    input,
  )) {
    (Ended(), _) => LinkStep(this),
    (_, RadioOutageBegan(:final outage)) => _end(
      EndedByRadioOutage(outage),
      at,
    ),
    (Linked(), ServicesDiscovered()) => _enter(const Ready()),
    (Ready(), ServicesDiscovered()) => LinkStep(this),
    (
      UpPhase(),
      RadioReported(report: LinkReport.connecting || LinkReport.connected),
    ) =>
      LinkStep(this),
    (final UpPhase up, RadioReported(report: LinkReport.disconnecting)) =>
      _enter(Closing(returnTo: up, by: ClosingBy.radio)),
    (
      UpPhase(),
      RadioReported(report: LinkReport.disconnected) || ReportsEnded(),
    ) =>
      _end(const EndedByDrop(), at),
    (final UpPhase up, DisconnectRequested()) => _enter(
      Closing(returnTo: up, by: ClosingBy.request),
      duty: const CloseTheLink(),
    ),
    (UpPhase(), CloseConfirmed() || CloseFailed()) => LinkStep(this),
    (Closing(), ServicesDiscovered()) => LinkStep(this),
    (
      Closing(),
      RadioReported(
        report: LinkReport.connecting ||
            LinkReport.connected ||
            LinkReport.disconnecting,
      ),
    ) =>
      LinkStep(this),
    (
      Closing(:final by),
      RadioReported(report: LinkReport.disconnected) || ReportsEnded(),
    ) =>
      _end(_endOfClosingBy(by), at),
    (Closing(by: ClosingBy.request || ClosingBy.both), DisconnectRequested()) =>
      LinkStep(this),
    (Closing(:final returnTo, by: ClosingBy.radio), DisconnectRequested()) =>
      _stay(
        Closing(returnTo: returnTo, by: ClosingBy.both),
        duty: const CloseTheLink(),
      ),
    (Closing(by: ClosingBy.request || ClosingBy.both), CloseConfirmed()) =>
      _end(const EndedOnRequest(), at),
    (Closing(:final returnTo, by: ClosingBy.request), CloseFailed()) => _enter(
      returnTo,
    ),
    (Closing(:final returnTo, by: ClosingBy.both), CloseFailed()) => _stay(
      Closing(returnTo: returnTo, by: ClosingBy.radio),
    ),
    (Closing(by: ClosingBy.radio), CloseConfirmed() || CloseFailed()) =>
      LinkStep(this),
  };

  static LinkEnd _endOfClosingBy(ClosingBy by) => switch (by) {
    ClosingBy.radio => const EndedByDrop(),
    ClosingBy.request || ClosingBy.both => const EndedOnRequest(),
  };

  LinkStep _enter(LinkPhase next, {LinkDuty? duty}) =>
      LinkStep(_in(next), duty: duty, entered: next);

  LinkStep _stay(Closing next, {LinkDuty? duty}) =>
      LinkStep(_in(next), duty: duty);

  LinkStep _end(LinkEnd end, DateTime at) => LinkStep(
    _in(Ended(end)),
    duty: ReleaseTheLink(end),
    entered: Ended(end),
    events: [LinkEnded(device: device, at: at, end: end)],
  );

  Link _in(LinkPhase next) => Link._(id: id, device: device, phase: next);
}

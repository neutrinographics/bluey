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

/// The link is up: start hearing what the radio says about it.
final class FollowTheLink extends LinkDuty {
  const FollowTheLink(this.id);

  /// The link to follow, as the platform knows it.
  final LinkId id;

  @override
  bool operator ==(Object other) => other is FollowTheLink && other.id == id;

  @override
  int get hashCode => Object.hash(FollowTheLink, id);
}

/// The open failed: nothing was acquired for the link, so let it go.
final class ForgetTheLink extends LinkDuty {
  const ForgetTheLink();

  @override
  bool operator ==(Object other) => other is ForgetTheLink;

  @override
  int get hashCode => (ForgetTheLink).hashCode;
}

/// Ask the platform to close the link, and feed its answer back.
final class CloseTheLink extends LinkDuty {
  const CloseTheLink(this.id);

  /// The link to close, as the platform knows it.
  final LinkId id;

  @override
  bool operator ==(Object other) => other is CloseTheLink && other.id == id;

  @override
  int get hashCode => Object.hash(CloseTheLink, id);
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
  LinkStep(
    this.link, {
    this.duty,
    this.entered,
    List<LinkEvent> events = const [],
  }) : events = List.unmodifiable(events);

  /// The link after the input.
  final Link link;

  /// What the owner must now do, or null when nothing is due.
  final LinkDuty? duty;

  /// The phase the step entered, or null when the link stayed in the same
  /// kind of phase, so an owner tells others of a move only when there was
  /// one: a closing link whose closer changed has not begun closing again.
  final LinkPhase? entered;

  /// What the step raised, in order; empty unless it began, opened or ended
  /// the link, so each is raised once in the link's life.
  final List<LinkEvent> events;
}

/// One link to a device and its lifecycle, from the moment its open is
/// asked for, which decides what every event does to the link and raises
/// every event the link's life tells of.
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
  /// A link to [device] whose open is asked for at [at]; the lifecycle
  /// starts at [Opening]. It is the only way to build a link, so every link
  /// has walked the lifecycle from its start and was told of as beginning.
  static LinkStep begin({required DeviceAddress device, required DateTime at}) {
    const opening = Opening();
    return LinkStep(
      Link._(id: null, device: device, phase: opening),
      entered: opening,
      events: [LinkOpenBegan(device: device, at: at)],
    );
  }

  const Link._({required this.id, required this.device, required this.phase});

  /// The platform's handle for the link, null until the open succeeds and
  /// for a link that never opened. It is not what tells one link from
  /// another: a platform may hand the next link to a device the last one's
  /// id, so Connection keys its links by device.
  final LinkId? id;

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
    Opening() || NeverOpened() || UpPhase() => null,
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
    (Ended() || NeverOpened(), _) => LinkStep(this),
    (Opening(), OpenSucceeded(:final id)) => _opened(id, at),
    (Opening(), OpenFailed()) => LinkStep(
      _in(const NeverOpened()),
      duty: const ForgetTheLink(),
      entered: const NeverOpened(),
    ),
    (Opening(), _) => LinkStep(this),
    (_, OpenSucceeded() || OpenFailed()) => LinkStep(this),
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
      duty: CloseTheLink(_upId),
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
        duty: CloseTheLink(_upId),
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

  /// The id of a link that has opened; only such a link can be closed, so
  /// asking it of one that has not is a fault in this class.
  LinkId get _upId =>
      id ?? (throw StateError('The link to $device has not opened.'));

  LinkStep _opened(LinkId id, DateTime at) {
    const linked = Linked();
    return LinkStep(
      Link._(id: id, device: device, phase: linked),
      duty: FollowTheLink(id),
      entered: linked,
      events: [LinkOpened(device: device, at: at)],
    );
  }

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

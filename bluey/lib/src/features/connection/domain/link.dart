import 'package:meta/meta.dart';

import '../../../shared/domain/device_address.dart';
import 'connection_state.dart';
import 'link_end.dart';
import 'link_id.dart';
import 'link_input.dart';

/// What the owner of a link must now do because of a step, which the link
/// cannot do itself: it touches no radio and holds nothing to release.
enum LinkDuty {
  /// Ask the platform to close the link, and feed its answer back.
  closeTheLink,

  /// The link has ended: release what lives as long as it and announce the
  /// end.
  releaseAndAnnounce,
}

/// The answer to one input: the link as it now stands, and the duty, if any,
/// that the input left its owner.
final class LinkStep {
  const LinkStep(this.link, [this.duty]);

  /// The link after the input.
  final Link link;

  /// What the owner must now do, or null when nothing is due.
  final LinkDuty? duty;
}

/// One link to a device and its lifecycle, which decides what every event
/// does to the link.
///
/// It is a value: [on] answers the next link and leaves this one as it was,
/// so one owner can keep the only current copy. An ended link is final, so a
/// late or repeated event can never revive it or change why it ended.
@immutable
final class Link {
  /// A link the platform has just connected; the lifecycle starts at
  /// [ConnectionState.linked]. It is the only way to build a link, so an
  /// ended link without a [LinkEnd] cannot exist.
  const Link.opened({required this.id, required this.device})
    : state = ConnectionState.linked,
      end = null,
      _upState = ConnectionState.linked,
      _closeAsked = false,
      _radioClosing = false;

  const Link._({
    required this.id,
    required this.device,
    required this.state,
    required this.end,
    required ConnectionState upState,
    required bool closeAsked,
    required bool radioClosing,
  }) : _upState = upState,
       _closeAsked = closeAsked,
       _radioClosing = radioClosing;

  /// Which link this is.
  final LinkId id;

  /// The device the link reaches.
  final DeviceAddress device;

  /// Where the link stands in its lifecycle.
  final ConnectionState state;

  /// Why the link ended; non-null exactly when it has.
  final LinkEnd? end;

  /// The state a closing link goes back to if the close it asked for fails.
  final ConnectionState _upState;

  /// Whether a close was asked of the platform and has not been answered.
  final bool _closeAsked;

  /// Whether the radio itself reported the link closing.
  final bool _radioClosing;

  /// The end the link has reached, or the one a closing link is heading for;
  /// null while the link is up.
  LinkEnd? get endInSight {
    if (end != null) return end;
    return isClosing ? _headingFor : null;
  }

  LinkEnd get _headingFor =>
      _closeAsked ? const EndedOnRequest() : const EndedByDrop();

  /// Whether the link is up, linked or ready.
  bool get isUp => state.isConnected;

  /// Whether the link is being closed.
  bool get isClosing => state == ConnectionState.disconnecting;

  /// Whether the link has ended, for good.
  bool get hasEnded => end != null;

  /// Answers what [input] does to this link.
  LinkStep on(LinkInput input) {
    if (hasEnded) return LinkStep(this);
    return isClosing ? _onWhileClosing(input) : _onWhileUp(input);
  }

  LinkStep _onWhileUp(LinkInput input) => switch (input) {
    ServicesDiscovered() => LinkStep(_up(ConnectionState.ready)),
    RadioReported(report: LinkReport.connecting || LinkReport.connected) =>
      LinkStep(this),
    RadioReported(report: LinkReport.disconnecting) => LinkStep(
      _closing(closeAsked: false, radioClosing: true),
    ),
    RadioReported(report: LinkReport.disconnected) ||
    ReportsEnded() => _ended(ConnectionState.disconnected, const EndedByDrop()),
    DisconnectRequested() => LinkStep(
      _closing(closeAsked: true, radioClosing: false),
      LinkDuty.closeTheLink,
    ),
    CloseConfirmed() || CloseFailed() => LinkStep(this),
    RadioOutageBegan(:final outage) => _invalidated(outage),
  };

  LinkStep _onWhileClosing(LinkInput input) => switch (input) {
    ServicesDiscovered() => LinkStep(this),
    RadioReported(report: LinkReport.connecting || LinkReport.connected) =>
      LinkStep(this),
    RadioReported(report: LinkReport.disconnecting) => LinkStep(
      _closing(closeAsked: _closeAsked, radioClosing: true),
    ),
    RadioReported(report: LinkReport.disconnected) ||
    ReportsEnded() => _ended(ConnectionState.disconnected, _headingFor),
    DisconnectRequested() when _closeAsked => LinkStep(this),
    DisconnectRequested() => LinkStep(
      _closing(closeAsked: true, radioClosing: _radioClosing),
      LinkDuty.closeTheLink,
    ),
    CloseConfirmed() when _closeAsked => _ended(
      ConnectionState.disconnected,
      const EndedOnRequest(),
    ),
    CloseFailed() when _closeAsked && !_radioClosing => LinkStep(_up(_upState)),
    CloseFailed() when _closeAsked => LinkStep(
      _closing(closeAsked: false, radioClosing: true),
    ),
    CloseConfirmed() || CloseFailed() => LinkStep(this),
    RadioOutageBegan(:final outage) => _invalidated(outage),
  };

  Link _up(ConnectionState upState) => _with(
    state: upState,
    upState: upState,
    closeAsked: false,
    radioClosing: false,
  );

  Link _closing({required bool closeAsked, required bool radioClosing}) =>
      _with(
        state: ConnectionState.disconnecting,
        upState: _upState,
        closeAsked: closeAsked,
        radioClosing: radioClosing,
      );

  LinkStep _invalidated(RadioOutage outage) =>
      _ended(ConnectionState.invalidated, EndedByRadioOutage(outage));

  LinkStep _ended(ConnectionState endState, LinkEnd end) => LinkStep(
    _with(
      state: endState,
      end: end,
      upState: _upState,
      closeAsked: false,
      radioClosing: false,
    ),
    LinkDuty.releaseAndAnnounce,
  );

  Link _with({
    required ConnectionState state,
    LinkEnd? end,
    required ConnectionState upState,
    required bool closeAsked,
    required bool radioClosing,
  }) => Link._(
    id: id,
    device: device,
    state: state,
    end: end,
    upState: upState,
    closeAsked: closeAsked,
    radioClosing: radioClosing,
  );
}

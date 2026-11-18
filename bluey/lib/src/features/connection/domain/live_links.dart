import 'package:meta/meta.dart';

import '../../../shared/domain/device_address.dart';
import 'link.dart';

/// Who asks for a device's link: the app, which holds a link until it lets
/// it go, or a borrower, which uses one for a while and gives it back.
enum LinkUser { app, borrower }

/// What a caller asking for a device's link must do.
enum Admission {
  /// Open a link; the caller's attempt is the only one for the device.
  open,

  /// Wait for the open or close in flight to settle, then ask again.
  wait,

  /// Use the link that is up; nothing is opened.
  reuse,
}

/// What a give-back leaves the owner of the link to do.
enum AfterGiveBack {
  /// Nobody uses the link any more: close it.
  closeTheLink,

  /// Someone still uses the link, or there is none: leave it as it is.
  leaveIt,
}

/// Who may open, reuse and close each device's link, so that one device never
/// has two attempts at once and a borrower's give-back never closes a link
/// the app holds.
///
/// It is a value that answers decisions and touches no radio. It keeps no copy
/// of a link's state: a caller asking about a device whose link came up hands
/// that link in, and is answered from it. A device whose give-back answered
/// [AfterGiveBack.closeTheLink] stays known, used by nobody, until its owner
/// forgets it once the close has ended the link.
@immutable
final class LiveLinks {
  /// No device has a link or an attempt in flight.
  const LiveLinks.empty() : _entries = const {};

  const LiveLinks._(this._entries);

  final Map<DeviceAddress, _Entry> _entries;

  /// Answers whether [user] opens, waits for or reuses [device]'s link, and
  /// the table with the user recorded when it opens or reuses.
  ///
  /// [link] is the device's link when it has one, and null while none exists
  /// or an open is in flight. A waiter is not recorded: it asks again.
  (LiveLinks, Admission) admit(
    DeviceAddress device,
    LinkUser user, {
    required Link? link,
  }) {
    final entry = _entries[device];
    if (entry == null) {
      return (_with(device, _Entry.opening(user)), Admission.open);
    }
    if (entry.opening) return (this, Admission.wait);
    if (link == null) {
      throw StateError('The link to $device came up; ask with that link.');
    }
    if (!link.isUp) return (this, Admission.wait);
    return (_with(device, entry.joinedBy(user)), Admission.reuse);
  }

  /// The attempt in flight for [device] came up.
  LiveLinks opened(DeviceAddress device) => _changed(device, (e) => e.up());

  /// Removes [device], whose open failed or whose link ended, so the next
  /// caller opens a new link.
  LiveLinks forget(DeviceAddress device) =>
      LiveLinks._(Map.unmodifiable({..._entries}..remove(device)));

  /// One borrower fewer on [device]'s link, and whether the link must now
  /// close: only when no borrower is left and the app does not hold it.
  ///
  /// Only a borrower of a link that came up gives it back; a give-back while
  /// the open is in flight is not part of the contract. A give-back on a
  /// known device that no borrower uses is a [StateError], since it would
  /// hide the next borrower and close the link under them.
  (LiveLinks, AfterGiveBack) giveBack(DeviceAddress device) {
    final entry = _entries[device];
    if (entry == null) return (this, AfterGiveBack.leaveIt);
    final after = entry.lessOneBorrower(device);
    final answer =
        after.inUse ? AfterGiveBack.leaveIt : AfterGiveBack.closeTheLink;
    return (_with(device, after), answer);
  }

  /// One borrower fewer on [device]'s link, which the app now holds.
  ///
  /// As with [giveBack], a keep on a known device that no borrower uses is a
  /// [StateError].
  LiveLinks keep(DeviceAddress device) =>
      _changed(device, (e) => e.lessOneBorrower(device).heldByTheApp());

  /// Whether the app holds [device]'s link, or the attempt it started.
  bool appHolds(DeviceAddress device) => _entries[device]?.appHolds ?? false;

  /// How many borrowers use [device]'s link, or the attempt one started.
  int borrowersOf(DeviceAddress device) => _entries[device]?.borrowers ?? 0;

  /// Whether an attempt to open [device]'s link is in flight.
  bool isOpening(DeviceAddress device) => _entries[device]?.opening ?? false;

  LiveLinks _changed(DeviceAddress device, _Entry Function(_Entry) change) {
    final entry = _entries[device];
    return entry == null ? this : _with(device, change(entry));
  }

  LiveLinks _with(DeviceAddress device, _Entry entry) =>
      LiveLinks._(Map.unmodifiable({..._entries, device: entry}));
}

@immutable
final class _Entry {
  const _Entry({
    required this.opening,
    required this.appHolds,
    required this.borrowers,
  });

  _Entry.opening(LinkUser user)
    : this(
        opening: true,
        appHolds: user == LinkUser.app,
        borrowers: user == LinkUser.borrower ? 1 : 0,
      );

  final bool opening;
  final bool appHolds;
  final int borrowers;

  bool get inUse => appHolds || borrowers > 0;

  _Entry up() =>
      _Entry(opening: false, appHolds: appHolds, borrowers: borrowers);

  _Entry joinedBy(LinkUser user) => switch (user) {
    LinkUser.app => heldByTheApp(),
    LinkUser.borrower => _Entry(
      opening: opening,
      appHolds: appHolds,
      borrowers: borrowers + 1,
    ),
  };

  _Entry heldByTheApp() =>
      _Entry(opening: opening, appHolds: true, borrowers: borrowers);

  _Entry lessOneBorrower(DeviceAddress device) {
    if (borrowers == 0) {
      throw StateError('No borrower uses the link to $device.');
    }
    return _Entry(
      opening: opening,
      appHolds: appHolds,
      borrowers: borrowers - 1,
    );
  }
}

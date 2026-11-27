import '../../../shared/domain/device_address.dart';
import 'live_link.dart';

/// Who asks for a device's link: the app, which holds a link until it lets
/// it go, or a borrower, which uses one for a while and gives it back.
enum LinkUser { app, borrower }

/// What a caller asking for a device's link must do.
sealed class Admission<L extends LiveLink> {
  const Admission();
}

/// Open [link], which the table now holds as the device's only attempt.
final class Open<L extends LiveLink> extends Admission<L> {
  const Open(this.link);

  /// The device's link, begun for the caller and not yet open.
  final L link;
}

/// Wait for the open or close in flight to settle, then ask again.
final class Wait<L extends LiveLink> extends Admission<L> {
  const Wait();
}

/// Use [link], which is up; nothing is opened.
final class Reuse<L extends LiveLink> extends Admission<L> {
  const Reuse(this.link);

  /// The device's link, now also used by the caller.
  final L link;
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
/// It holds each device's link, so its owner keeps no second table, and
/// touches no radio. It is generic only so the owner gets back the type of
/// link it put in. A device whose give-back answered
/// [AfterGiveBack.closeTheLink] stays known, used by nobody, until its link
/// has ended.
final class LiveLinks<L extends LiveLink> {
  final Map<DeviceAddress, _Entry<L>> _entries = {};

  /// Answers whether [user] opens, waits for or reuses [device]'s link, and
  /// records the user when it opens or reuses. A waiter is not recorded: it
  /// asks again.
  ///
  /// Only the opener's [begin] is called, so the table holds the device's
  /// link from the moment its open begins and no caller can begin a second.
  Admission<L> admit(
    DeviceAddress device,
    LinkUser user, {
    required L Function() begin,
  }) {
    final entry = _entries[device];
    if (entry == null) {
      final link = begin();
      _entries[device] = _Entry<L>(link)..joinedBy(user);
      return Open<L>(link);
    }
    if (!entry.link.isUp) return Wait<L>();
    entry.joinedBy(user);
    return Reuse<L>(entry.link);
  }

  /// [link], begun for [device], did not open, so the next caller opens.
  /// Matched by identity, as [ended] is.
  void notOpened(DeviceAddress device, L link) => ended(device, link);

  /// One borrower fewer on [device]'s [link], and whether the link must now
  /// close: only when no borrower is left and the app does not hold it.
  ///
  /// The app never gives a link back here: it lets go by closing the link.
  /// A give-back of a link that is no longer [device]'s, an old one whose
  /// successor came up, changes nothing. A give-back on [device]'s link
  /// that no borrower uses is a [StateError], since it would hide the next
  /// borrower and close the link under them.
  AfterGiveBack givenBack(DeviceAddress device, L link) {
    final entry = _liveEntryOf(device, link);
    if (entry == null) return AfterGiveBack.leaveIt;
    entry.lessOneBorrower(device);
    return entry.inUse ? AfterGiveBack.leaveIt : AfterGiveBack.closeTheLink;
  }

  /// One borrower fewer on [device]'s [link], which the app now holds.
  ///
  /// As with [givenBack], a keep of an old link changes nothing, and a keep
  /// on a link that no borrower uses is a [StateError].
  void kept(DeviceAddress device, L link) {
    _liveEntryOf(device, link)
      ?..lessOneBorrower(device)
      ..joinedBy(LinkUser.app);
  }

  /// [link] to [device] has ended, so the next caller opens. Matched by
  /// identity, so an old link's end never drops the link that followed it.
  void ended(DeviceAddress device, L link) {
    if (_liveEntryOf(device, link) != null) _entries.remove(device);
  }

  /// [device]'s entry when [link] is the link it holds, matched by identity
  /// so an old holder never touches its successor.
  _Entry<L>? _liveEntryOf(DeviceAddress device, L link) {
    final entry = _entries[device];
    return identical(entry?.link, link) ? entry : null;
  }
}

/// A device's link, from the moment its open begins, and who uses it.
final class _Entry<L extends LiveLink> {
  _Entry(this.link);

  final L link;
  bool _appHolds = false;
  int _borrowers = 0;

  bool get inUse => _appHolds || _borrowers > 0;

  void joinedBy(LinkUser user) => switch (user) {
    LinkUser.app => _appHolds = true,
    LinkUser.borrower => _borrowers++,
  };

  void lessOneBorrower(DeviceAddress device) {
    if (_borrowers == 0) {
      throw StateError('No borrower uses the link to $device.');
    }
    _borrowers--;
  }
}

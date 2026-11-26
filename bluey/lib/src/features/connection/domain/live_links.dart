import '../../../shared/domain/device_address.dart';
import 'live_link.dart';

/// Who asks for a device's link: the app, which holds a link until it lets
/// it go, or a borrower, which uses one for a while and gives it back.
enum LinkUser { app, borrower }

/// What a caller asking for a device's link must do.
sealed class Admission<L extends LiveLink> {
  const Admission();
}

/// Open a link; the caller's attempt is the only one for the device.
final class Open<L extends LiveLink> extends Admission<L> {
  const Open();
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
  /// records the user when it reuses. A waiter is not recorded: it asks again.
  Admission<L> admit(DeviceAddress device, LinkUser user) {
    final entry = _entries[device];
    if (entry == null) {
      _entries[device] = _Entry<L>();
      return Open<L>();
    }
    final link = entry.link;
    if (link == null || link.isClosing) return Wait<L>();
    entry.joinedBy(user);
    return Reuse<L>(link);
  }

  /// The attempt [user] started for [device] came up as [link].
  void opened(DeviceAddress device, LinkUser user, L link) =>
      _entries[device] = _Entry<L>(link)..joinedBy(user);

  /// The attempt in flight for [device] failed, so the next caller opens.
  void notOpened(DeviceAddress device) {
    if (_entries[device]?.link == null) _entries.remove(device);
  }

  /// One user fewer on [device]'s link, and whether the link must now close:
  /// only when no borrower is left and the app does not hold it.
  ///
  /// Only a user of a link that came up gives it back; a give-back while the
  /// open is in flight is not part of the contract. A give-back by a user who
  /// does not use a known device's link is a [StateError], since it would
  /// hide the next user and close the link under them.
  AfterGiveBack givenBack(DeviceAddress device, LinkUser user) {
    final entry = _entries[device];
    if (entry == null) return AfterGiveBack.leaveIt;
    entry.leftBy(user, device);
    return entry.inUse ? AfterGiveBack.leaveIt : AfterGiveBack.closeTheLink;
  }

  /// One borrower fewer on [device]'s link, which the app now holds.
  ///
  /// As with [givenBack], a keep on a known device that no borrower uses is a
  /// [StateError].
  void kept(DeviceAddress device) {
    final entry = _entries[device];
    if (entry == null) return;
    entry
      ..leftBy(LinkUser.borrower, device)
      ..joinedBy(LinkUser.app);
  }

  /// [link] to [device] has ended, so the next caller opens. Matched by
  /// identity, so an old link's end never drops the link that followed it.
  void ended(DeviceAddress device, L link) {
    if (identical(_entries[device]?.link, link)) _entries.remove(device);
  }
}

/// A device's link, null while the open is in flight, and who uses it.
final class _Entry<L extends LiveLink> {
  _Entry([this.link]);

  final L? link;
  bool _appHolds = false;
  int _borrowers = 0;

  bool get inUse => _appHolds || _borrowers > 0;

  void joinedBy(LinkUser user) => switch (user) {
    LinkUser.app => _appHolds = true,
    LinkUser.borrower => _borrowers++,
  };

  void leftBy(LinkUser user, DeviceAddress device) {
    switch (user) {
      case LinkUser.app:
        if (!_appHolds) {
          throw StateError('The app does not hold the link to $device.');
        }
        _appHolds = false;
      case LinkUser.borrower:
        if (_borrowers == 0) {
          throw StateError('No borrower uses the link to $device.');
        }
        _borrowers--;
    }
  }
}

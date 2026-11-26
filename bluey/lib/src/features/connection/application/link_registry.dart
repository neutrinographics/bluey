import 'dart:async';

import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link.dart';
import '../domain/link_event.dart';
import '../domain/link_id.dart';
import '../domain/live_links.dart';
import 'borrowed_link.dart';
import 'connection_log_words.dart';
import 'link_session.dart';
import 'ports/link_events.dart';
import 'ports/links.dart';

const _timedOut = ConnectFailed(ConnectFailureReason.timeout);

/// The one place that knows which device has a live link and who is using
/// it, so a device never has two platform connects at once and a borrower's
/// give-back never closes a link the app holds.
///
/// It carries out what [LiveLinks] decides, and that table is the one place
/// it keeps each device's [LinkSession]; everything it asks of a live link it
/// asks through that session, and the table drops a device as part of its
/// link's teardown.
/// Everything is keyed by device, since a platform may give the next link to
/// a device the id of the last one.
final class LinkRegistry {
  LinkRegistry({
    required Links links,
    required LinkEvents events,
    required Log log,
    required Now now,
  }) : _links = links,
       _events = events,
       _log = log,
       _now = now;

  final Links _links;
  final LinkEvents _events;
  final Log _log;
  final Now _now;
  final Map<DeviceAddress, Completer<void>> _changes = {};
  final LiveLinks<LinkSession> _table = LiveLinks<LinkSession>();

  /// The session of [device]'s link, opened if there is none, held by the
  /// app until it lets it go.
  Future<Either<ConnectionFailure, LinkSession>> hold(
    DeviceAddress device, {
    Duration? timeout,
  }) => _acquire(device, LinkUser.app, timeout);

  /// A borrower's hold on [device]'s link, opened if there is none, whose
  /// give-back closes the link only when nobody else uses it.
  Future<Either<ConnectionFailure, BorrowedLink>> borrow(
    DeviceAddress device, {
    Duration? timeout,
  }) async {
    final answer = await _acquire(device, LinkUser.borrower, timeout);
    return answer.map(
      (session) => BorrowedLink(
        session: session,
        giveBack: () => _giveBack(session),
        keep: () => _keep(session),
      ),
    );
  }

  /// The session of the device's link for [by]. [timeout] is this caller's
  /// whole budget: its wait for another caller's attempt and its own attempt
  /// share it.
  ///
  /// A caller that meets an open or a close in flight waits for it to settle
  /// and asks again, so it never inherits another caller's failure or a link
  /// about to end. Running out of time while waiting answers a connect
  /// timeout and leaves the attempt in flight alone.
  Future<Either<ConnectionFailure, LinkSession>> _acquire(
    DeviceAddress device,
    LinkUser by,
    Duration? timeout,
  ) async {
    final deadline = timeout == null ? null : _now().add(timeout);
    var budget = timeout;
    while (true) {
      switch (_table.admit(device, by)) {
        case Reuse(:final link):
          return Right(link);
        case Open():
          return _open(device, by, budget);
        case Wait():
          if (!await _changed(device, deadline)) return const Left(_timedOut);
          budget = _timeLeft(deadline);
          if (budget != null && budget <= Duration.zero) {
            return const Left(_timedOut);
          }
      }
    }
  }

  /// One borrower fewer on [session]'s link, closing it when nobody is left.
  ///
  /// Answers the close's failure when it fails, which leaves the link up for
  /// the next caller to reuse. A session that is no longer the device's
  /// changes nothing.
  Future<Either<ConnectionFailure, void>> _giveBack(LinkSession session) {
    final after = _table.givenBack(session.link.device, session);
    if (after == AfterGiveBack.leaveIt) return Future.value(const Right(null));
    return session.disconnect();
  }

  /// Hands a borrower's hold on [session]'s link to the app, which then holds
  /// it until it lets it go. A session that is no longer the device's
  /// changes nothing.
  void _keep(LinkSession session) => _table.kept(session.link.device, session);

  Future<Either<ConnectionFailure, LinkSession>> _open(
    DeviceAddress device,
    LinkUser by,
    Duration? timeout,
  ) async {
    _events.raise(LinkOpenBegan(device: device, at: _now()));
    _logDevice(device, 'connect started');
    final answer = await _links.open(device, timeout: timeout);
    switch (answer) {
      case Left(:final value):
        _table.notOpened(device);
        _logFailure(device, value);
        _announceChange(device);
        return Left(value);
      case Right(:final value):
        final session = _sessionOf(device, by, value);
        _logDevice(device, 'connect succeeded');
        _announceChange(device);
        return Right(session);
    }
  }

  /// The session of the link just opened, stored before the open is told
  /// of, so whoever hears of it finds the device's link live.
  LinkSession _sessionOf(DeviceAddress device, LinkUser by, LinkId id) {
    final opened = Link.open(id: id, device: device, at: _now());
    final session = LinkSession(
      link: opened.link,
      links: _links,
      events: _events,
      log: _log,
      now: _now,
    );
    _table.opened(device, by, session);
    session.phases.listen((_) => _announceChange(device));
    session.onEnd((_) => _ended(session));
    opened.events.forEach(_events.raise);
    return session;
  }

  void _ended(LinkSession session) {
    final device = session.link.device;
    _table.ended(device, session);
    _announceChange(device);
  }

  /// Waits for [device]'s next change, an open settling, a live link's state
  /// moving or a link forgotten, and answers false when [deadline] comes
  /// first. Every state move counts, so a close that fails wakes the waiter
  /// whoever asked for it.
  Future<bool> _changed(DeviceAddress device, DateTime? deadline) async {
    final change = (_changes[device] ??= Completer<void>()).future;
    if (deadline == null) {
      await change;
      return true;
    }
    return change
        .then((_) => true)
        .timeout(deadline.difference(_now()), onTimeout: () => false);
  }

  void _announceChange(DeviceAddress device) =>
      _changes.remove(device)?.complete();

  Duration? _timeLeft(DateTime? deadline) => deadline?.difference(_now());

  void _logFailure(DeviceAddress device, ConnectionFailure failure) {
    final type = failure.runtimeType.toString();
    _log.log(
      BlueyLogLevel.error,
      connectionLogContext,
      'connect failed',
      data: {'address': device.value, 'exception': type},
      errorCode: type,
    );
  }

  void _logDevice(DeviceAddress device, String message) => _log.log(
    BlueyLogLevel.info,
    connectionLogContext,
    message,
    data: {'address': device.value},
  );
}

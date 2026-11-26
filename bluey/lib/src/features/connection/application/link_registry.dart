import 'dart:async';

import '../../../shared/application/event_publisher.dart';
import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/application/now.dart';
import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_event.dart';
import '../domain/connection_failure.dart';
import '../domain/link.dart';
import '../domain/link_id.dart';
import '../domain/live_links.dart';
import 'connection_log_words.dart';
import 'link_session.dart';
import 'ports/links.dart';

const _timedOut = ConnectFailed(ConnectFailureReason.timeout);

/// The one place that knows which device has a live link and who is using
/// it, so a device never has two platform connects at once and a borrower's
/// give-back never closes a link the app holds.
///
/// It carries out what [LiveLinks] decides and keeps no link state of its
/// own: everything it asks of a live link it asks through that link's
/// [LinkSession], and it forgets a device as part of its link's teardown.
/// Everything is keyed by device, since a platform may give the next link to
/// a device the id of the last one.
final class LinkRegistry {
  LinkRegistry({
    required Links links,
    required EventPublisher events,
    required Log log,
    required Now now,
  }) : _links = links,
       _events = events,
       _log = log,
       _now = now;

  final Links _links;
  final EventPublisher _events;
  final Log _log;
  final Now _now;
  final Map<DeviceAddress, LinkSession> _sessions = {};
  final Map<DeviceAddress, Completer<void>> _changes = {};
  LiveLinks _table = const LiveLinks.empty();

  /// The session of the device's link for [by], opened if there is none.
  /// [timeout] is this caller's whole budget: its wait for another caller's
  /// attempt and its own attempt share it.
  ///
  /// A caller that meets an open or a close in flight waits for it to settle
  /// and asks again, so it never inherits another caller's failure or a link
  /// about to end. Running out of time while waiting answers a connect
  /// timeout and leaves the attempt in flight alone.
  Future<Either<ConnectionFailure, LinkSession>> acquire(
    DeviceAddress device, {
    required LinkUser by,
    Duration? timeout,
  }) async {
    final deadline = timeout == null ? null : _now().add(timeout);
    var budget = timeout;
    while (true) {
      final session = _sessions[device];
      final (table, admission) = _table.admit(device, by, link: session?.link);
      _table = table;
      switch (admission) {
        case Admission.reuse:
          return Right(session!);
        case Admission.open:
          return _open(device, budget);
        case Admission.wait:
          if (!await _changed(device, deadline)) return const Left(_timedOut);
          budget = _timeLeft(deadline);
          if (budget != null && budget <= Duration.zero) {
            return const Left(_timedOut);
          }
      }
    }
  }

  /// One user fewer on [session]'s link, closing it when nobody is left.
  ///
  /// Answers the close's failure when it fails, which leaves the link up for
  /// the next caller to reuse. A session that is no longer the device's live
  /// session changes nothing.
  Future<Either<ConnectionFailure, void>> giveBack(LinkSession session) {
    final device = session.link.device;
    if (!_isLive(session)) return Future.value(const Right(null));
    final (table, after) = _table.giveBack(device);
    _table = table;
    if (after == AfterGiveBack.leaveIt) return Future.value(const Right(null));
    return session.disconnect();
  }

  /// Hands a borrower's hold on [session]'s link to the app, which then holds
  /// it until it lets it go. A session that is no longer the device's live
  /// session changes nothing.
  void keep(LinkSession session) {
    if (_isLive(session)) _table = _table.keep(session.link.device);
  }

  Future<Either<ConnectionFailure, LinkSession>> _open(
    DeviceAddress device,
    Duration? timeout,
  ) async {
    _events.emit(ConnectingEvent(deviceAddress: device));
    _logDevice(device, 'connect started');
    final answer = await _links.open(device, timeout: timeout);
    switch (answer) {
      case Left(:final value):
        _table = _table.forget(device);
        _logFailure(device, value);
        _announceChange(device);
        return Left(value);
      case Right(:final value):
        final session = _sessionOf(device, value);
        _events.emit(ConnectedEvent(deviceAddress: device));
        _logDevice(device, 'connect succeeded');
        _announceChange(device);
        return Right(session);
    }
  }

  LinkSession _sessionOf(DeviceAddress device, LinkId id) {
    final session = LinkSession(
      link: Link.opened(id: id, device: device),
      links: _links,
      events: _events,
      log: _log,
    );
    _sessions[device] = session;
    _table = _table.opened(device);
    session.phases.listen((_) => _announceChange(device));
    session.onEnd((_) => _forget(session));
    return session;
  }

  void _forget(LinkSession session) {
    final device = session.link.device;
    if (!_isLive(session)) return;
    _sessions.remove(device);
    _table = _table.forget(device);
    _announceChange(device);
  }

  bool _isLive(LinkSession session) =>
      identical(_sessions[session.link.device], session);

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

import 'dart:async';

import '../../../shared/application/event_publisher.dart';
import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_event.dart';
import '../domain/connection_failure.dart';
import '../domain/connection_state.dart';
import '../domain/link.dart';
import '../domain/link_end.dart';
import '../domain/link_input.dart';
import 'ports/links.dart';

const _context = 'bluey.connection';

/// Runs one link: it feeds the [Link] what the radio and the caller say, does
/// what the link answers, and releases everything tied to the link when it
/// ends, so no owner of a connection repeats the teardown or keeps a copy of
/// the link's state.
///
/// Once the link has ended the session never addresses the platform with its
/// id again, since the platform may already have given that id to the next
/// link to the same device.
final class LinkSession {
  /// Starts listening to the link's reports and to radio outages at once.
  LinkSession({
    required Link link,
    required Links links,
    required EventPublisher events,
    required Log log,
  }) : _link = link,
       _links = links,
       _events = events,
       _log = log {
    _reports = links
        .reportsOf(link.id)
        .listen(
          (report) => _feed(RadioReported(report)),
          onDone: () => _feed(const ReportsEnded()),
        );
    _outages = links.outages.listen(
      (outage) => _feed(RadioOutageBegan(outage)),
    );
  }

  final Links _links;
  final EventPublisher _events;
  final Log _log;
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  final List<FutureOr<void> Function(LinkEnd end)> _releases = [];
  final List<void Function(LinkEnd end)> _operationsUp = [];
  final Completer<void> _released = Completer<void>();
  late final StreamSubscription<LinkReport> _reports;
  late final StreamSubscription<RadioOutage> _outages;
  Link _link;
  Future<Either<ConnectionFailure, void>>? _closeInFlight;

  /// The link as it stands now; the session holds the only current copy.
  Link get link => _link;

  /// Every state the link moves to. Carries no errors, and ends when the link
  /// ends.
  Stream<ConnectionState> get states => _states.stream;

  /// Registers something that lives as long as the link. Runs once when the
  /// link ends, whatever ended it; at once if the teardown has finished.
  ///
  /// A release must not wait on this session's [disconnect], which answers
  /// only once every release has run, so the two would wait on each other.
  void onEnd(FutureOr<void> Function(LinkEnd end) release) {
    if (_released.isCompleted) {
      unawaited(_runRelease(release, _link.end!));
    } else {
      _releases.add(release);
    }
  }

  /// Tells the link its services are known, which makes GATT operations safe
  /// on it.
  void servicesDiscovered() => _feed(const ServicesDiscovered());

  /// Runs [operation] if the link is up, and answers [orEnd] instead if the
  /// link is closing, has ended, or ends before the operation answers.
  ///
  /// The operation is not stopped when the link ends first; its late answer
  /// is dropped, so no caller waits on a dead link.
  Future<Either<F, T>> whileUp<F, T>(
    Future<Either<F, T>> Function() operation, {
    required F Function(LinkEnd end) orEnd,
  }) {
    final endInSight = _link.endInSight;
    if (endInSight != null) return Future.value(Left(orEnd(endInSight)));
    final ended = Completer<Either<F, T>>();
    void answerEnd(LinkEnd end) => ended.complete(Left(orEnd(end)));
    _operationsUp.add(answerEnd);
    return Future.any([
      Future.sync(operation),
      ended.future,
    ]).whenComplete(() => _operationsUp.remove(answerEnd));
  }

  /// Ends the link on request, and answers once everything tied to it has
  /// been released.
  ///
  /// A call while a close is in flight answers with that close, and a call on
  /// an ended link answers success without asking the platform. A failed
  /// close leaves the link as it was, unless the link ended anyway.
  Future<Either<ConnectionFailure, void>> disconnect() {
    final inFlight = _closeInFlight;
    if (inFlight != null) return inFlight;
    if (_link.hasEnded) return _afterRelease();
    _logDevice('disconnect entered');
    _feed(const DisconnectRequested());
    return _closeInFlight!;
  }

  void _feed(LinkInput input) {
    final before = _link.state;
    final step = _link.on(input);
    _link = step.link;
    if (_link.state != before) _announceState();
    switch (step.duty) {
      case LinkDuty.closeTheLink:
        _closeInFlight = _close();
      case LinkDuty.releaseAndAnnounce:
        unawaited(_release(_link.end!));
      case null:
        break;
    }
  }

  void _announceState() {
    _log.log(
      BlueyLogLevel.info,
      _context,
      'state transition',
      data: {'deviceId': '${_link.device}', 'state': '${_link.state}'},
    );
    _states.add(_link.state);
  }

  Future<Either<ConnectionFailure, void>> _close() async {
    final answer = await _links.close(_link.id);
    _closeInFlight = null;
    if (answer case Left(:final value) when !_link.hasEnded) {
      _feed(const CloseFailed());
      return Left(value);
    }
    _feed(const CloseConfirmed());
    final released = await _afterRelease();
    _logDevice('disconnect resolved');
    return released;
  }

  Future<Either<ConnectionFailure, void>> _afterRelease() =>
      _released.future.then((_) => const Right(null));

  Future<void> _release(LinkEnd end) async {
    unawaited(_states.close());
    for (final answerEnd in List.of(_operationsUp)) {
      _guarded('end answer failed', () => answerEnd(end));
    }
    _operationsUp.clear();
    _events.emit(
      DisconnectedEvent(deviceAddress: _link.device, reason: _reasonOf(end)),
    );
    unawaited(_reports.cancel());
    unawaited(_outages.cancel());
    for (var next = 0; next < _releases.length; next++) {
      await _runRelease(_releases[next], end);
    }
    _releases.clear();
    _released.complete();
  }

  Future<void> _runRelease(
    FutureOr<void> Function(LinkEnd end) release,
    LinkEnd end,
  ) async {
    try {
      await release(end);
    } catch (error) {
      _warn('release failed', error);
    }
  }

  /// Runs a caller's callback during the teardown, so one that throws is
  /// logged and the teardown goes on.
  void _guarded(String message, void Function() callback) {
    try {
      callback();
    } catch (error) {
      _warn(message, error);
    }
  }

  void _warn(String message, Object error) => _log.log(
    BlueyLogLevel.warn,
    _context,
    message,
    data: {'deviceId': '${_link.device}', 'error': '$error'},
    errorCode: error.runtimeType.toString(),
  );

  static String _reasonOf(LinkEnd end) => switch (end) {
    EndedOnRequest() => 'requested',
    EndedByDrop() => 'linkLoss',
    EndedByRadioOutage() => 'radioOutage',
  };

  void _logDevice(String message) => _log.log(
    BlueyLogLevel.info,
    _context,
    message,
    data: {'deviceId': '${_link.device}'},
  );
}

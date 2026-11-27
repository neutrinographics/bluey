import 'dart:async';

import '../../../shared/application/log.dart';
import '../../../shared/application/log_level.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/link_end.dart';
import 'connection_log_words.dart';
import 'link_session.dart';

/// The last value the radio reported for one link, which a session answers
/// from and its listeners follow, so the rules of who outranks whom live in
/// one place for every reading a link holds.
///
/// A report or a value taken outranks the first read, which may answer after
/// either; so does the link's end. A failed first read leaves the initial
/// value and is only logged, since nobody asked for it and so nobody could
/// catch it.
final class ReportedValue<T> {
  /// Follows [reports], when the radio reports any, and asks [readFirst]
  /// once, at once; all of it is let go when [session]'s link ends. A failed
  /// first read is logged as [failedReadLine], with the device and the
  /// failure's code.
  ReportedValue({
    required LinkSession session,
    required T initial,
    Stream<T>? reports,
    required Future<Either<ConnectionFailure, T>> Function() readFirst,
    required Log log,
    required String failedReadLine,
  }) : _held = initial {
    _reports = reports?.listen(take);
    unawaited(_readFirst(session, readFirst, log, failedReadLine));
    session.onEnd(_release);
  }

  /// A value nothing reports or reads, for a platform whose radio has none:
  /// it stays [value], and its changes are that value and then the end.
  ReportedValue.unreported(T value) : _held = value {
    unawaited(_changes.close());
  }

  final StreamController<T> _changes = StreamController<T>.broadcast();
  StreamSubscription<T>? _reports;
  T _held;
  bool _taken = false;

  /// The value as the radio last reported it, or the initial one until it
  /// does.
  T get value => _held;

  /// The value as it is now, then every value reported or taken, to each
  /// listener; it ends when the link ends.
  Stream<T> follow() => Stream.multi((listener) {
    listener.add(_held);
    if (_changes.isClosed) {
      unawaited(listener.close());
      return;
    }
    final followed = _changes.stream.listen(
      listener.add,
      onDone: listener.close,
    );
    listener.onCancel = followed.cancel;
  });

  /// Holds [value], as a report or a request the radio granted brings it;
  /// after the link's end it is held for whoever reads it, and followed by
  /// nobody.
  void take(T value) {
    _taken = true;
    _held = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  Future<void> _readFirst(
    LinkSession session,
    Future<Either<ConnectionFailure, T>> Function() read,
    Log log,
    String failedReadLine,
  ) async {
    final answer = await read();
    answer.fold(
      (failure) => log.log(
        BlueyLogLevel.warn,
        connectionLogContext,
        failedReadLine,
        data: {
          'deviceId': '${session.link.device}',
          'exception': failureCodeOf(failure),
        },
      ),
      (value) {
        if (!_taken && !session.link.hasEnded) _held = value;
      },
    );
  }

  void _release(LinkEnd end) {
    unawaited(_reports?.cancel());
    _reports = null;
    unawaited(_changes.close());
  }
}

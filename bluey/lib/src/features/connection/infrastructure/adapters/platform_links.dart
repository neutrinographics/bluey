import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/application/log.dart';
import '../../../../shared/application/log_level.dart';
import '../../../../shared/domain/device_address.dart';
import '../../../../shared/domain/either.dart';
import '../../application/ports/links.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_end.dart';
import '../../domain/link_id.dart';
import '../../domain/link_input.dart';
import 'platform_failures.dart';

/// Connection's [Links] over [BlueyPlatform], so the lifecycle runs on a
/// phone exactly as it runs over the in-memory double.
///
/// A link's id is the connection id the platform answers, which the GATT
/// calls that follow are made with. The adapter cannot tell an ended link's
/// id from its successor's, so it trusts the port's rule that an ended
/// link's id is not used again.
///
/// A platform stream that fails is logged and ended, never passed on, which
/// the lifecycle reads as a drop; the adapter then asks the platform to
/// close the link, since nobody else will.
final class PlatformLinks implements Links {
  PlatformLinks(BlueyPlatform platform, {required Log log})
    : _platform = platform,
      _log = log;

  final BlueyPlatform _platform;
  final Log _log;
  final Map<LinkId, _CarriedReports> _reports = {};

  @override
  Future<Either<ConnectionFailure, LinkId>> open(
    DeviceAddress device, {
    Duration? timeout,
  }) async {
    final answer = await answering(
      'connect',
      () => _platform.connect(
        device.value,
        PlatformConnectConfig(timeoutMs: timeout?.inMilliseconds, mtu: null),
      ),
    );
    return answer.map(_carry);
  }

  @override
  Future<Either<ConnectionFailure, void>> close(LinkId link) async {
    final reports = _reports[link];
    if (reports == null || reports.ended) return const Right(null);
    final answer = await answering(
      'disconnect',
      () => _platform.disconnect(link.value),
    );
    return answer.fold(
      (failure) {
        if (reports.ended) return const Right(null);
        return Left(failure);
      },
      (_) {
        reports.end();
        return const Right(null);
      },
    );
  }

  @override
  Stream<LinkReport> reportsOf(LinkId link) =>
      _reports[link]?.stream ?? const Stream.empty();

  @override
  Stream<RadioOutage> get outages => _platform.stateStream.transform(
    StreamTransformer.fromHandlers(
      handleData: (state, sink) {
        final outage = _outageOf(state);
        if (outage != null) sink.add(outage);
      },
      handleError: (_, _, sink) => sink.add(RadioOutage.unknown),
    ),
  );

  /// Starts carrying the link's reports in the turn its id arrives, and
  /// keeps the reports already carried when the link is still live, so a
  /// second open never detaches the listener of the first.
  LinkId _carry(String connectionId) {
    final link = LinkId(connectionId);
    final live = _reports[link];
    if (live == null || live.ended) {
      _reports[link] = _CarriedReports(
        _platform.connectionStateStream(connectionId),
        onFailure: (error) => _closeAfterFailedReports(connectionId, error),
      );
    }
    return link;
  }

  /// The lifecycle reads failed reports as a drop and will not ask for a
  /// close, so the adapter asks, or the radio link could stay up with
  /// nothing left able to close it.
  void _closeAfterFailedReports(String connectionId, Object error) {
    _log.log(
      BlueyLogLevel.warn,
      'bluey.connection',
      'link reports failed',
      data: {'link': connectionId},
      errorCode: error.runtimeType.toString(),
    );
    unawaited(
      answering('disconnect', () => _platform.disconnect(connectionId)).then(
        (answer) => answer.fold(
          (failure) => _log.log(
            BlueyLogLevel.warn,
            'bluey.connection',
            'link left open',
            data: {'device': connectionId},
            errorCode: failure.runtimeType.toString(),
          ),
          (_) {},
        ),
      ),
    );
  }
}

/// One link's reports, buffered until its one listener arrives and ended
/// for good once the platform stops, fails, the link is closed or its
/// listener leaves.
///
/// A listener leaves only when its link has ended for Connection, as after
/// a radio outage, while the platform may still hold the link; the next open
/// of that device then carries its reports afresh for its new reader.
final class _CarriedReports {
  _CarriedReports(
    Stream<PlatformConnectionState> states, {
    required void Function(Object error) onFailure,
  }) {
    _subscription = states.listen(
      (state) => _controller.add(_reportOf(state)),
      onError: (Object error) {
        end();
        onFailure(error);
      },
      onDone: end,
    );
  }

  late final StreamController<LinkReport> _controller = StreamController(
    onCancel: end,
  );
  late final StreamSubscription<PlatformConnectionState> _subscription;

  Stream<LinkReport> get stream => _controller.stream;

  bool get ended => _controller.isClosed;

  void end() {
    if (ended) return;
    unawaited(_subscription.cancel());
    unawaited(_controller.close());
  }
}

LinkReport _reportOf(PlatformConnectionState state) => switch (state) {
  PlatformConnectionState.connecting => LinkReport.connecting,
  PlatformConnectionState.connected => LinkReport.connected,
  PlatformConnectionState.disconnecting => LinkReport.disconnecting,
  PlatformConnectionState.disconnected => LinkReport.disconnected,
};

RadioOutage? _outageOf(BluetoothState state) => switch (state) {
  BluetoothState.on => null,
  BluetoothState.off => RadioOutage.off,
  BluetoothState.unauthorized => RadioOutage.unauthorized,
  BluetoothState.unsupported => RadioOutage.unsupported,
  BluetoothState.unknown => RadioOutage.unknown,
};

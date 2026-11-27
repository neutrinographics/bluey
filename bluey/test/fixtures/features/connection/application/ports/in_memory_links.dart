import 'dart:async';

import 'package:bluey/src/features/connection/application/ports/links.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';

import 'links_contract.dart';

/// A radio in memory, so Connection's application units can be tested
/// against [Links] without a platform, with time that `fakeAsync` drives.
///
/// It is its own [LinksHarness], and adds what those tests need: how long an
/// open or a close stays in flight, reports told by hand, and counts of what
/// was asked of it.
class InMemoryLinks implements Links, LinksHarness {
  /// How long an open stays in flight, whether it links or fails.
  Duration openDelay = Duration.zero;

  /// How long a close stays in flight, whether it succeeds or fails.
  Duration closeDelay = Duration.zero;

  final Set<DeviceAddress> _reachable = {};
  final Map<DeviceAddress, ConnectFailureReason> _openFailures = {};
  final Set<DeviceAddress> _closeFailures = {};
  final Map<DeviceAddress, LinkId> _live = {};
  final Map<LinkId, DeviceAddress> _devices = {};
  final Map<LinkId, StreamController<LinkReport>> _reports = {};
  final Map<DeviceAddress, int> _opens = {};
  final Map<DeviceAddress, int> _closes = {};
  final List<Duration?> _openTimeouts = [];
  final Map<DeviceAddress, CloseSignals> _closeOrders = {};
  final Map<DeviceAddress, Completer<void>> _heldAnswers = {};
  final StreamController<RadioOutage> _outages =
      StreamController<RadioOutage>.broadcast();

  @override
  Links get links => this;

  @override
  Future<Either<ConnectionFailure, LinkId>> open(
    DeviceAddress device, {
    Duration? timeout,
  }) async {
    _opens[device] = opensAsked(device) + 1;
    _openTimeouts.add(timeout);
    final failure = _openFailures.remove(device);
    if (timeout != null && openDelay > timeout) {
      await Future<void>.delayed(timeout);
      return const Left(ConnectFailed(ConnectFailureReason.timeout));
    }
    await Future<void>.delayed(openDelay);
    if (failure != null) return Left(ConnectFailed(failure));
    if (!_reachable.contains(device)) {
      return const Left(ConnectFailed(ConnectFailureReason.deviceNotFound));
    }
    return Right(_live[device] ?? _mint(device));
  }

  /// Closes the link live when the close was asked for, and only that one,
  /// so a close still in flight when its link ends never closes the next.
  @override
  Future<Either<ConnectionFailure, void>> close(LinkId link) async {
    final device = _devices[link];
    if (device != null) _closes[device] = closesAsked(device) + 1;
    final asked = device == null ? null : _live[device];
    final fails = device != null && _closeFailures.remove(device);
    await Future<void>.delayed(closeDelay);
    if (device == null || asked != link || !identical(_live[device], asked)) {
      return const Right(null);
    }
    if (fails) {
      return const Left(
        UnexpectedPlatformFailure('the close was told to fail'),
      );
    }
    if (_closeOrders[device] == CloseSignals.reportThenAnswer) {
      drop(device);
      final answer = Completer<void>();
      _heldAnswers[device] = answer;
      await answer.future;
      return const Right(null);
    }
    _end(device);
    return const Right(null);
  }

  @override
  Stream<LinkReport> reportsOf(LinkId link) =>
      _reports[link]?.stream ?? const Stream.empty();

  @override
  Stream<RadioOutage> get outages => _outages.stream;

  @override
  void reach(DeviceAddress device) => _reachable.add(device);

  @override
  void failNextOpen(DeviceAddress device, ConnectFailureReason reason) =>
      _openFailures[device] = reason;

  @override
  void failNextClose(DeviceAddress device) => _closeFailures.add(device);

  @override
  void drop(DeviceAddress device) {
    report(device, LinkReport.disconnected);
    _end(device);
  }

  @override
  void outage(RadioOutage outage) => _outages.add(outage);

  /// A close that answers first never reports afterwards: the radio here
  /// keeps a late report with the link it is about.
  @override
  void orderCloseSignals(DeviceAddress device, CloseSignals order) =>
      _closeOrders[device] = order;

  /// The radio says [report] about [device]'s link.
  void report(DeviceAddress device, LinkReport report) =>
      _reports[_linkOf(device)]!.add(report);

  /// How many times an open of [device] was asked for.
  int opensAsked(DeviceAddress device) => _opens[device] ?? 0;

  /// How many times a close of [device]'s link was asked for.
  int closesAsked(DeviceAddress device) => _closes[device] ?? 0;

  /// The timeout each open was asked with, in order.
  List<Duration?> get openTimeouts => List.unmodifiable(_openTimeouts);

  /// Names the link by its device's address, the hardest naming the port
  /// allows: a link opened after an ended one answers the same id and
  /// replaces the ended link's entry, as on the platforms.
  LinkId _mint(DeviceAddress device) {
    final link = LinkId(device.value);
    _live[device] = link;
    _devices[link] = device;
    _reports[link] = StreamController<LinkReport>();
    _heldAnswers.remove(device)?.complete();
    return link;
  }

  LinkId _linkOf(DeviceAddress device) =>
      _live[device] ??
      (throw StateError('$device has no link for the radio to talk about'));

  void _end(DeviceAddress device) {
    final link = _linkOf(device);
    _live.remove(device);
    _reports[link]!.close().ignore();
  }
}

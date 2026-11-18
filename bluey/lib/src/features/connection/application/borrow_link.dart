import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import '../domain/live_links.dart';
import 'link_registry.dart';
import 'link_session.dart';

/// What a borrower asks for: a device by its address, and the borrower's
/// budget.
final class BorrowLinkRequest {
  const BorrowLinkRequest({required this.device, this.timeout});

  /// The device whose link to borrow.
  final DeviceAddress device;

  /// The borrower's whole budget, waiting included; null leaves the bound to
  /// the platform.
  final Duration? timeout;
}

/// A borrower's access to a device's link, opened for it if there is none,
/// so a short use of a link closes only what nobody else is using.
final class BorrowLink {
  const BorrowLink(this._registry);

  final LinkRegistry _registry;

  /// Answers the borrower's hold on the device's link.
  Future<Either<ConnectionFailure, BorrowedLink>> run(
    BorrowLinkRequest request,
  ) async {
    final answer = await _registry.acquire(
      request.device,
      by: LinkUser.borrower,
      timeout: request.timeout,
    );
    return answer.map((session) => BorrowedLink._(_registry, session));
  }
}

/// A borrower's hold on a link. The first of [giveBack] and [keep] takes
/// effect; later calls do nothing.
final class BorrowedLink {
  BorrowedLink._(this._registry, this.session);

  final LinkRegistry _registry;
  bool _ended = false;

  /// The borrowed link's session.
  final LinkSession session;

  /// Ends the borrow; the link closes only if nobody else uses it, and a
  /// failed close is answered.
  Future<Either<ConnectionFailure, void>> giveBack() {
    if (_ended) return Future.value(const Right(null));
    _ended = true;
    return _registry.giveBack(session);
  }

  /// Ends the borrow by handing the link to the app, which then holds it.
  void keep() {
    if (_ended) return;
    _ended = true;
    _registry.keep(session);
  }
}

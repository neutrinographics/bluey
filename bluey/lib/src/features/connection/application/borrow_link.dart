import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import 'borrowed_link.dart';
import 'link_registry.dart';

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
  ) => _registry.borrow(request.device, timeout: request.timeout);
}

import '../../features/connection/application/borrow_link.dart';
import '../../shared/domain/device_address.dart';
import '../failure_translation.dart';
import 'connection.dart';
import 'connections.dart';

/// A link in use for a short task by code that is not the app, seen through
/// the public [Connection] alone, so the borrower names nothing of
/// Connection's application.
///
/// The first of [giveBack] and [keep] counts and later calls do nothing, as
/// the borrow [borrowingThrough] makes it from holds.
final class BorrowedConnection {
  BorrowedConnection({
    required this.connection,
    required Future<void> Function() giveBack,
    required void Function() keep,
  }) : _giveBack = giveBack,
       _keep = keep;

  /// The borrowed link's Connection, the very object the app gets for it.
  final Connection connection;

  final Future<void> Function() _giveBack;
  final void Function() _keep;

  /// Ends the borrow; the link closes only if nobody else uses it.
  ///
  /// Throws a BlueyException when the close fails, and the link then stays
  /// as it was.
  Future<void> giveBack() => _giveBack();

  /// Ends the borrow by handing the link to the app, which then holds it and
  /// must disconnect it itself.
  void keep() => _keep();
}

/// How a borrower gets a device's link, opened for it if there is none.
///
/// Throws a BlueyException when the link cannot be had.
typedef BorrowConnection =
    Future<BorrowedConnection> Function(
      DeviceAddress device, {
      Duration? timeout,
    });

/// A [BorrowConnection] over [borrowLink], whose Connections come from
/// [connections], so a borrower and the app holding one link hold one
/// object.
BorrowConnection borrowingThrough({
  required BorrowLink borrowLink,
  required Connections connections,
}) => (DeviceAddress device, {Duration? timeout}) async {
  final borrowed = valueOrThrow(
    await borrowLink.run(BorrowLinkRequest(device: device, timeout: timeout)),
    device: device,
  );
  return BorrowedConnection(
    connection: connections.of(borrowed.session),
    giveBack:
        () async => valueOrThrow(await borrowed.giveBack(), device: device),
    keep: borrowed.keep,
  );
};

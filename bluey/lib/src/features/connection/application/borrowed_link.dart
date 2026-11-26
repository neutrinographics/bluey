import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import 'link_session.dart';

/// A borrower's hold on a link. The first of [giveBack] and [keep] takes
/// effect; later calls do nothing.
final class BorrowedLink {
  /// A hold on [session] that ends through [giveBack] or [keep]. Only
  /// `LinkRegistry.borrow` makes one, so every hold is one the table counts.
  BorrowedLink({
    required this.session,
    required Future<Either<ConnectionFailure, void>> Function() giveBack,
    required void Function() keep,
  }) : _giveBack = giveBack,
       _keep = keep;

  final Future<Either<ConnectionFailure, void>> Function() _giveBack;
  final void Function() _keep;
  bool _ended = false;

  /// The borrowed link's session.
  final LinkSession session;

  /// Ends the borrow; the link closes only if nobody else uses it, and a
  /// failed close is answered.
  Future<Either<ConnectionFailure, void>> giveBack() {
    if (_ended) return Future.value(const Right(null));
    _ended = true;
    return _giveBack();
  }

  /// Ends the borrow by handing the link to the app, which then holds it.
  void keep() {
    if (_ended) return;
    _ended = true;
    _keep();
  }
}

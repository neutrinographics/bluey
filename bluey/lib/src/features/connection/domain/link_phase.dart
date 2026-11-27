import 'package:meta/meta.dart';

import 'link_end.dart';

/// Where a link stands in its lifecycle, in Connection's own words; the edge
/// translates it for apps, so the lifecycle can say what apps were never
/// told, such as who is closing a link and where a failed close returns it.
@immutable
sealed class LinkPhase {
  const LinkPhase();
}

/// The link is up, so a failed close of ours can return it here.
sealed class UpPhase extends LinkPhase {
  const UpPhase();
}

/// The platform connected the link; its services are not known yet, so GATT
/// operations are not safe on it.
final class Linked extends UpPhase {
  const Linked();

  @override
  bool operator ==(Object other) => other is Linked;

  @override
  int get hashCode => (Linked).hashCode;
}

/// The link's services are known, so GATT operations are safe on it.
final class Ready extends UpPhase {
  const Ready();

  @override
  bool operator ==(Object other) => other is Ready;

  @override
  int get hashCode => (Ready).hashCode;
}

/// Who is closing a link, which decides both why it will end and whether a
/// failed close of ours brings it back up.
enum ClosingBy {
  /// We asked the platform to close it.
  request,

  /// The radio is closing it on its own.
  radio,

  /// The radio was closing it when we asked as well.
  both,
}

/// The link is being closed.
final class Closing extends LinkPhase {
  const Closing({required this.returnTo, required this.by});

  /// Where a failed close of ours returns the link.
  final UpPhase returnTo;

  /// Who is closing the link: our request, the radio, or both.
  final ClosingBy by;

  @override
  bool operator ==(Object other) =>
      other is Closing && other.returnTo == returnTo && other.by == by;

  @override
  int get hashCode => Object.hash(Closing, returnTo, by);
}

/// The link has ended, for good.
final class Ended extends LinkPhase {
  const Ended(this.end);

  /// Why the link ended.
  final LinkEnd end;

  @override
  bool operator ==(Object other) => other is Ended && other.end == end;

  @override
  int get hashCode => Object.hash(Ended, end);
}

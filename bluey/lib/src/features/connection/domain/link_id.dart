import 'package:meta/meta.dart';

/// Names one link as the platform names it, and is what the platform is
/// addressed with for that link.
///
/// A platform may name a later link to the same device by the same id, so an
/// id must not be used once its link has ended: it may already name the
/// link that came after.
@immutable
final class LinkId {
  const LinkId(this.value);

  /// The text the id was minted from; opaque to everything but equality.
  final String value;

  @override
  bool operator ==(Object other) => other is LinkId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

import 'package:meta/meta.dart';

/// Names one link, so that two links to the same device, one after the
/// other, are never mistaken for each other.
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

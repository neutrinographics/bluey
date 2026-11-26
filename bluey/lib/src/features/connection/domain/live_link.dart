/// What the table of live links reads of a link it holds, so the table
/// decides in Connection's own words and knows nothing of how a link is run.
abstract interface class LiveLink {
  /// Whether the link is on its way out, closing or ended but not yet let
  /// go of, so a caller arriving now must wait for it rather than reuse it.
  bool get isClosing;
}

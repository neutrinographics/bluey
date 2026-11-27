/// What the table of live links reads of a link it holds, so the table
/// decides in Connection's own words and knows nothing of how a link is run.
abstract interface class LiveLink {
  /// Whether the link is up, linked or ready, so a caller arriving now may
  /// reuse it; one still opening, closing or ended must be waited for.
  bool get isUp;
}

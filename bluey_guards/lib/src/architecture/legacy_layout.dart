/// Which of today's folders under `lib/src` already stand for a bounded
/// context and which for the shared kernel, so the boundary rule holds code
/// that has not moved yet to the boundaries it will have once it does.
final class LegacyLayout {
  /// Today's [contexts] and today's [shared] kernel folders.
  const LegacyLayout({required this.contexts, required this.shared});

  /// Folders under `lib/src` that are a context today, each the name of the
  /// context it is (`connection`, `discovery`).
  final Set<String> contexts;

  /// Folders under `lib/src` that are kernel today (`shared`, `log`).
  final Set<String> shared;
}

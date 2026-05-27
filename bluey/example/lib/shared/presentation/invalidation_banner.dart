import 'package:flutter/material.dart';

/// Inline banner shown on a feature screen when its underlying
/// bluey-derived instance has been invalidated (adapter cycle, etc.).
/// Tapping the action triggers the centralized recovery flow.
class InvalidationBanner extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback onRecover;

  const InvalidationBanner({
    super.key,
    this.label = 'Bluetooth was cycled. Tap to recover.',
    this.actionLabel = 'Recover',
    required this.onRecover,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(label),
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      actions: [
        TextButton(onPressed: onRecover, child: Text(actionLabel)),
      ],
    );
  }
}

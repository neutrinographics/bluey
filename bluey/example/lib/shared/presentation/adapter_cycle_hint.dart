import 'package:flutter/material.dart';

/// Quiet, always-visible footer text on lifecycle-sensitive screens.
/// Tells the user how to exercise the recovery flow without requiring
/// a debug-only API in the bluey library.
class AdapterCycleHint extends StatelessWidget {
  const AdapterCycleHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Tip: toggle Bluetooth in system settings to see recovery in action.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).hintColor,
            ),
      ),
    );
  }
}

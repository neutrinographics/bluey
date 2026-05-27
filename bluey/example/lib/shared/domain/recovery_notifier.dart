import 'package:flutter/foundation.dart';

/// Broadcasts a tick whenever the shared [Bluey] instance is recreated.
/// Screens listen and rebuild their [BlocProvider] keyed off the tick
/// so their cubits are reconstructed with fresh use cases.
class RecoveryNotifier extends ValueNotifier<int> {
  RecoveryNotifier() : super(0);

  void notify() {
    value = value + 1;
  }
}

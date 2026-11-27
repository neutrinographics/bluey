import '../../../../fixtures/features/connection/application/ports/in_memory_signal_strength.dart';
import '../../../../fixtures/features/connection/application/ports/signal_strength_contract.dart';

void main() {
  signalStrengthContract(
    'InMemorySignalStrength',
    () async => InMemorySignalStrength(),
  );
}

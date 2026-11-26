import '../../../../fixtures/features/connection/application/ports/bonding_contract.dart';
import '../../../../fixtures/features/connection/application/ports/in_memory_bonding.dart';

void main() {
  bondingContract('InMemoryBonding', () async => InMemoryBonding());
}

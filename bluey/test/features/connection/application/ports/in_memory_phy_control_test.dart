import '../../../../fixtures/features/connection/application/ports/in_memory_phy_control.dart';
import '../../../../fixtures/features/connection/application/ports/phy_control_contract.dart';

void main() {
  phyControlContract('InMemoryPhyControl', () async => InMemoryPhyControl());
}

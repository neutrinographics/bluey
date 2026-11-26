import '../../../../fixtures/features/connection/application/ports/in_memory_mtu_negotiation.dart';
import '../../../../fixtures/features/connection/application/ports/mtu_negotiation_contract.dart';

void main() {
  mtuNegotiationContract(
    'InMemoryMtuNegotiation',
    () async => InMemoryMtuNegotiation(),
  );
}

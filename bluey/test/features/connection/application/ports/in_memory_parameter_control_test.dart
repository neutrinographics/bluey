import '../../../../fixtures/features/connection/application/ports/in_memory_parameter_control.dart';
import '../../../../fixtures/features/connection/application/ports/parameter_control_contract.dart';

void main() {
  parameterControlContract(
    'InMemoryParameterControl',
    () async => InMemoryParameterControl(),
  );
}

import 'package:bluey_guards/architecture.dart';

import 'bluey_platform_interface_architecture.dart';

void main() {
  holdToKnownViolations(
    package,
    tree: readPackage(),
    anchor: anchor,
    rules: packageRules,
    lists: readKnownViolations(),
  );
}

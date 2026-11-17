import 'package:bluey_guards/architecture.dart';

import 'bluey_ios_architecture.dart';

void main() {
  holdToKnownViolations(
    package,
    tree: readPackage(),
    anchor: anchor,
    rules: packageRules,
    lists: readKnownViolations(),
  );
}

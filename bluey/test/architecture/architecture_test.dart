import 'package:bluey_guards/architecture.dart';

import 'bluey_architecture.dart';

void main() {
  holdToKnownViolations(
    'bluey',
    tree: readBluey(),
    anchor: 'lib/bluey.dart',
    rules: blueyRules,
    lists: readKnownViolations(),
  );
}

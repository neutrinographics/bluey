import 'package:bluey_guards/architecture.dart';

import 'bluey_guards_architecture.dart';

/// The guards are held to the rules they hold the other packages to that
/// apply to a package with no layers: no file too long to read whole, and a
/// public library that exports only its own code.
void main() {
  holdToKnownViolations(
    package,
    tree: readPackage(),
    anchor: anchor,
    rules: packageRules,
    lists: readKnownViolations(),
  );
}

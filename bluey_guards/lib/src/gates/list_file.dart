import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Every top-level list of strings in a list file's [source], by its name,
/// read from the syntax tree so a gate compares what the lists hold and never
/// how a diff happens to lay their lines out.
///
/// A list file holds lists and nothing else (a package's
/// `test/architecture/known_violations.dart`, its known-defect roster). An
/// entry that is not a plain string, one built by interpolation or named by
/// a constant, is refused with a [ListFileRefusal]: a gate that cannot read
/// an entry as written cannot say whether the list grew.
Map<String, List<String>> readLists(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  return {
    for (final declaration
        in unit.declarations.whereType<TopLevelVariableDeclaration>())
      for (final variable in declaration.variables.variables)
        if (variable.initializer case ListLiteral(:final elements))
          variable.name.lexeme: [
            for (final element in elements) _entryOf(variable, element),
          ],
  };
}

/// Why a list file could not be read, naming the list and the entry.
final class ListFileRefusal implements Exception {
  /// A refusal that says [message].
  const ListFileRefusal(this.message);

  /// What could not be read, and where.
  final String message;

  @override
  String toString() => message;
}

String _entryOf(VariableDeclaration list, CollectionElement element) {
  if (element is StringLiteral) {
    if (element.stringValue case final value?) return value;
  }
  throw ListFileRefusal(
    'The list ${list.name.lexeme} holds an entry that is not a plain '
    'string: ${element.toSource()}',
  );
}

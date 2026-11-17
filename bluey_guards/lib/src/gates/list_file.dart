import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Every top-level list of strings in a list file's [source], by its name,
/// read from the syntax tree so a gate compares what the lists hold and never
/// how a diff happens to lay their lines out.
///
/// A list file holds lists and nothing else (a package's
/// `test/architecture/known_violations.dart`, its known-defect roster), so
/// any other declaration is refused with a [ListFileRefusal]: a getter, a
/// function, a class, or a variable whose value is anything but a list
/// literal (`[...].toList()`, a set literal). A gate that skipped such a
/// declaration would never compare the list it builds, and a list could grow
/// past the gate by one token. An entry that is not a plain string, one built
/// by interpolation or named by a constant, is refused too: a gate that
/// cannot read an entry as written cannot say whether the list grew, and
/// neither can one that reads a file that does not parse.
Map<String, List<String>> readLists(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors case [final error, ...]) {
    throw ListFileRefusal('The list file does not parse: ${error.message}');
  }
  final unit = parsed.unit;
  final lists = <String, List<String>>{};
  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) {
      throw ListFileRefusal(
        'A list file holds lists and nothing else, not: '
        '${_firstLine(declaration)}',
      );
    }
    for (final variable in declaration.variables.variables) {
      lists[variable.name.lexeme] = _listOf(variable);
    }
  }
  return lists;
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

List<String> _listOf(VariableDeclaration variable) {
  if (variable.initializer case ListLiteral(:final elements)) {
    return [for (final element in elements) _entryOf(variable, element)];
  }
  throw ListFileRefusal(
    'The list ${variable.name.lexeme} is not a list literal of plain '
    'strings: ${_firstLine(variable)}',
  );
}

String _firstLine(AstNode node) => node.toSource().split('\n').first;

String _entryOf(VariableDeclaration list, CollectionElement element) {
  if (element is StringLiteral) {
    if (element.stringValue case final value?) return value;
  }
  throw ListFileRefusal(
    'The list ${list.name.lexeme} holds an entry that is not a plain '
    'string: ${element.toSource()}',
  );
}

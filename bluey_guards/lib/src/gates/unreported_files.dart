import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'line_coverage.dart';

/// The files of [sources], path to text, that hold code that runs and that
/// [coverage] does not name, in path order.
///
/// A coverage report names only the libraries a test loaded, so a file no
/// test loads is simply absent and the percentage over the report never
/// falls for it. A file with nothing that runs, an enum, an interface or a
/// file of exports, is absent from every report and is not named.
List<String> unreportedFiles(
  Map<String, String> sources,
  LineCoverage coverage,
) => [
  for (final MapEntry(key: path, value: source)
      in sources.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
    if (!coverage.files.contains(path) && declaresCodeThatRuns(source)) path,
];

/// Whether [source] declares anything a coverage report would count: a body
/// (of a function, method, getter, setter or operator), a constructor, an
/// extension type, or a variable that is not a constant and has an
/// initializer.
///
/// The rule leans towards code that runs: a constructor counts even when it
/// is `const` and has no body, since it can still be called with `new`.
/// Wrongly counting a file fails the gate where a test should load it; wrongly
/// passing a file over would let it go unmeasured.
bool declaresCodeThatRuns(String source) {
  final finder = _RunningCodeFinder();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(finder);
  return finder.found;
}

final class _RunningCodeFinder extends GeneralizingAstVisitor<void> {
  bool found = false;

  @override
  void visitFunctionBody(FunctionBody node) {
    if (node is! EmptyFunctionBody) found = true;
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.externalKeyword == null) found = true;
  }

  /// An extension type's representation is a constructor a coverage report
  /// counts, even when the type declares nothing else.
  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    found = true;
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer != null && !node.isConst) found = true;
  }

  /// A doc comment's references parse as code but run nothing.
  @override
  void visitComment(Comment node) {}
}

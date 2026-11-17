import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:path/path.dart' as p;

/// The exported surface of the library at [libraryPath], as text.
///
/// Committed next to a package, the text makes every change to what an app
/// can import show in a diff, so a refactoring that changes the API by
/// accident is caught and one that means to is reviewed as an API change.
/// The text depends on what the library exports, never on the order its
/// declarations or members are written in.
///
/// [libraryPath] is relative to the working directory, or absolute. The
/// analysis is rooted at the package holding the library, so its own
/// package configuration resolves what it imports.
///
/// Throws an [ApiDumpRefusal] instead of answering text when the library, or a
/// library declaring something it exports, has an error-severity
/// diagnostic (the first few are named), or when the text would name
/// `InvalidType`, a type the analyzer could not resolve. Either means the
/// text would be wrong, as it is when a package is read before `pub get`
/// wrote its configuration, and would report a change that is not there.
Future<String> dumpPublicApi(String libraryPath) async {
  final path = p.normalize(p.absolute(libraryPath));
  final collection = AnalysisContextCollection(includedPaths: [path]);
  try {
    final session = collection.contextFor(path).currentSession;
    final result = await session.getResolvedLibrary(path);
    if (result is! ResolvedLibraryResult) {
      throw ApiDumpRefusal('Cannot resolve $libraryPath: $result');
    }
    final declarations = _exportedDeclarations(result.element);
    final errors = [
      ..._errorsIn(result),
      for (final library in _declaringLibraries(result.element, declarations))
        ..._errorsIn(await session.getResolvedLibraryByElement(library)),
    ];
    if (errors.isNotEmpty) {
      throw ApiDumpRefusal(
        'Cannot dump the public API of $libraryPath: it has '
        '${errors.length} error(s), so what it exports cannot be read '
        '(has pub get run?):\n'
        '${errors.take(_errorsNamed).join('\n')}',
      );
    }
    return _refuseUnresolvedTypes(libraryPath, _dump(declarations));
  } finally {
    await collection.dispose();
  }
}

/// Why the public API of a library could not be dumped. It is an outcome a
/// caller expects, such as a package read before `pub get`, so it is not a
/// [StateError], which means a bug.
final class ApiDumpRefusal implements Exception {
  /// A refusal that says [message].
  const ApiDumpRefusal(this.message);

  /// Why, naming the library and the first few errors.
  final String message;

  @override
  String toString() => message;
}

const _errorsNamed = 3;

/// Every exported declaration, by its name, in name order.
List<Element> _exportedDeclarations(LibraryElement library) {
  final declarations = <String, Element>{};
  for (final element in library.exportNamespace.definedNames2.values) {
    final declaration = _declarationOf(element);
    declarations[declaration.name ?? ''] = declaration;
  }
  final names = declarations.keys.toList()..sort();
  return [for (final name in names) declarations[name]!];
}

/// The libraries other than [root] that declare what it exports, the SDK's
/// left out, in URI order so the errors named are always the same ones.
List<LibraryElement> _declaringLibraries(
  LibraryElement root,
  List<Element> declarations,
) {
  final libraries = <Uri, LibraryElement>{
    for (final declaration in declarations)
      if (declaration.library case final library?)
        if (library != root && !library.isInSdk) library.uri: library,
  };
  final uris =
      libraries.keys.toList()
        ..sort((a, b) => a.toString().compareTo(b.toString()));
  return [for (final uri in uris) libraries[uri]!];
}

List<String> _errorsIn(SomeResolvedLibraryResult result) => switch (result) {
  ResolvedLibraryResult(:final units) => [
    for (final unit in units)
      for (final diagnostic in unit.diagnostics)
        if (diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR)
          '  ${unit.path}:'
              '${unit.lineInfo.getLocation(diagnostic.offset).lineNumber}: '
              '${diagnostic.message}',
  ],
  _ => ['  cannot be resolved: $result'],
};

/// The backstop for an unresolved type that no error names, as when an
/// `ignore` comment silences the error that caused it.
String _refuseUnresolvedTypes(String libraryPath, String dump) {
  final unresolved = [
    for (final line in dump.split('\n'))
      if (_invalidType.hasMatch(line)) '  ${line.trimLeft()}',
  ];
  if (unresolved.isEmpty) return dump;
  throw ApiDumpRefusal(
    'Cannot dump the public API of $libraryPath: it names '
    '${unresolved.length} type(s) the analyzer could not resolve '
    '(has pub get run?):\n'
    '${unresolved.take(_errorsNamed).join('\n')}',
  );
}

final _invalidType = RegExp(r'\bInvalidType\b');

String _dump(List<Element> declarations) {
  final lines = [
    for (final declaration in declarations) ..._block(declaration),
  ];
  return '${lines.join('\n')}\n';
}

/// A top-level variable is exported as the getter and setter the language
/// derives from it; the dump names the variable that was written instead.
Element _declarationOf(Element element) =>
    element is PropertyAccessorElement && element.isOriginVariable
        ? element.variable
        : element;

List<String> _block(Element declaration) => [
  _signature(declaration),
  if (declaration is InstanceElement)
    for (final member in _membersOf(declaration)) '  $member',
];

List<String> _membersOf(InstanceElement declaration) {
  final members = <Element>[
    if (declaration is InterfaceElement)
      ...declaration.constructors.where((c) => c.isOriginDeclaration),
    ...declaration.fields.where(
      (f) => f.isOriginDeclaration || f.isOriginDeclaringFormalParameter,
    ),
    ...declaration.getters.where((g) => g.isOriginDeclaration),
    ...declaration.setters.where((s) => s.isOriginDeclaration),
    ...declaration.methods.where((m) => m.isOriginDeclaration),
  ];
  return [
    for (final member in members)
      if (member.isPublic) _signature(member),
  ]..sort();
}

/// A declaration's signature with the modifiers `displayString()` leaves
/// out, since dropping `const` or `final` or turning a constructor into a
/// factory breaks an app as surely as changing a type.
String _signature(Element element) =>
    [..._modifiersOf(element), element.displayString()].join(' ');

/// An enum's values are static const fields to the analyzer, but they read
/// as the enum's values, so they carry no modifier; and a top-level function
/// is static to the analyzer, but only a member is static to a reader.
List<String> _modifiersOf(Element element) => switch (element) {
  ConstructorElement(:final isConst, :final isFactory) => [
    if (isConst) 'const',
    if (isFactory) 'factory',
  ],
  FieldElement(isEnumConstant: true) => const [],
  VariableElement(:final isLate, :final isConst, :final isFinal) => [
    if (element is FieldElement && element.isStatic) 'static',
    if (isLate) 'late',
    if (isConst) 'const',
    if (isFinal) 'final',
  ],
  ExecutableElement(:final isStatic) => [
    if (isStatic && element.enclosingElement is InstanceElement) 'static',
  ],
  _ => const [],
};

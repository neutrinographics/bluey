import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'source_file.dart';

/// What one Dart file names and where it raises, read from its syntax tree,
/// so a rule is never fooled by a directive or a `throw` in a comment or a
/// string.
final class DartSource {
  DartSource._({
    required this.path,
    required this.uris,
    required this.exports,
    required this.raises,
  });

  /// Parses [file]. A file that does not parse cleanly is still read as far
  /// as it goes, so one broken file never hides the rest of a package.
  factory DartSource.parse(SourceFile file) {
    final unit =
        parseString(
          content: file.content,
          path: file.path,
          throwIfDiagnostics: false,
        ).unit;
    final uris = <String>[];
    final exports = <String>[];
    for (final directive in unit.directives) {
      if (directive is NamespaceDirective) {
        final named =
            [
              directive.uri.stringValue,
              for (final alternative in directive.configurations)
                alternative.uri.stringValue,
            ].nonNulls;
        uris.addAll(named);
        if (directive is ExportDirective) exports.addAll(named);
      } else if (directive is PartDirective) {
        uris.addAll([directive.uri.stringValue].nonNulls);
      }
    }
    final finder = _RaiseFinder(unit.lineInfo);
    unit.accept(finder);
    return DartSource._(
      path: file.path,
      uris: List.unmodifiable(uris),
      exports: List.unmodifiable(exports),
      raises: List.unmodifiable(finder.raises),
    );
  }

  /// The package-relative path of the file.
  final String path;

  /// Every URI the file's imports, exports and parts name, each alternative
  /// of a conditional import included, in source order: what the file
  /// depends on.
  final List<String> uris;

  /// The URIs among [uris] that the file exports, which become part of its
  /// own surface.
  final List<String> exports;

  /// Every `throw`, `rethrow`, `Error.throwWithStackTrace`, `Future.error`
  /// and `Stream.error`, and every `addError` and `completeError` call and
  /// tear-off in the file, in source order: the places an error leaves it.
  final List<Raise> raises;

  @override
  String toString() => 'DartSource($path)';
}

/// One place a file raises an error, so a rule can name the line and what it
/// raises.
final class Raise {
  /// A raise on [line] of [what].
  const Raise({required this.line, required this.what});

  /// The 1-based line the raise is on.
  final int line;

  /// What is raised: `throw StateError`, `throw ArgumentError.value`,
  /// `throw e`, `rethrow`, `addError`, `completeError`, `Future.error` or
  /// `Stream.error`.
  final String what;

  @override
  bool operator ==(Object other) =>
      other is Raise && other.line == line && other.what == what;

  @override
  int get hashCode => Object.hash(line, what);

  @override
  String toString() => 'line $line: $what';
}

final class _RaiseFinder extends RecursiveAstVisitor<void> {
  _RaiseFinder(this._lines);

  final LineInfo _lines;
  final raises = <Raise>[];

  int _lineOf(int offset) => _lines.getLocation(offset).lineNumber;

  @override
  void visitThrowExpression(ThrowExpression node) {
    raises.add(
      Raise(
        line: _lineOf(node.throwKeyword.offset),
        what: 'throw ${_thrown(node.expression)}',
      ),
    );
    super.visitThrowExpression(node);
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    raises.add(Raise(line: _lineOf(node.offset), what: 'rethrow'));
    super.visitRethrowExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final what = _raisedBy(node);
    if (what != null) {
      raises.add(Raise(line: _lineOf(node.methodName.offset), what: what));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final (type, constructor) = _typeAndConstructor(node.constructorName);
    if (constructor == 'error' && _errorCreators.contains(type)) {
      raises.add(Raise(line: _lineOf(node.offset), what: '$type.error'));
    }
    super.visitInstanceCreationExpression(node);
  }

  /// Unresolved, `new Future.error(e)` reads as the type `error` behind an
  /// import prefix `Future`, since the parser cannot tell a prefix from a
  /// class; with no constructor name, the prefix is read as the class.
  (String, String?) _typeAndConstructor(ConstructorName name) {
    final type = name.type;
    final prefix = type.importPrefix;
    if (name.name == null && prefix != null) {
      return (prefix.name.lexeme, type.name.lexeme);
    }
    return (type.name.lexeme, name.name?.name);
  }

  /// A doc comment's references (`[StreamController.addError]`) parse as
  /// identifiers but raise nothing, so a comment is never walked.
  @override
  void visitComment(Comment node) {}

  /// A tear-off of `addError` or `completeError` (`onError: c.addError`,
  /// or a bare `onError: addError` inside a sink) forwards an error out of
  /// the file just as a call does. A call's name is counted with the call,
  /// and a named argument's label raises nothing, so neither is counted here.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final isCallName = parent is MethodInvocation && parent.methodName == node;
    if (_forwarders.contains(node.name) && !isCallName && parent is! Label) {
      raises.add(Raise(line: _lineOf(node.offset), what: node.name));
    }
    super.visitSimpleIdentifier(node);
  }

  /// What a call raises: a forwarded error, an error future or stream made
  /// with `Future.error` or `Stream.error`, or a throw through
  /// `Error.throwWithStackTrace`, named as a `throw` of its first argument
  /// so a programming error stays one.
  String? _raisedBy(MethodInvocation node) {
    final method = node.methodName.name;
    if (_forwarders.contains(method)) return method;
    final target = switch (node.target) {
      SimpleIdentifier(:final name) => name,
      PrefixedIdentifier(:final identifier) => identifier.name,
      _ => null,
    };
    if (method == 'error' && _errorCreators.contains(target)) {
      return '$target.error';
    }
    if (method == 'throwWithStackTrace' && target == 'Error') {
      final arguments = node.argumentList.arguments;
      return arguments.isEmpty ? 'throw' : 'throw ${_thrown(arguments.first)}';
    }
    return null;
  }
}

/// The members that hand an error on to whoever listens or awaits.
const _forwarders = {'addError', 'completeError'};

/// The classes whose `error` constructor makes a future or a stream that
/// fails.
const _errorCreators = {'Future', 'Stream'};

/// The name of what a `throw` raises: its expression up to the first `(`,
/// without a leading `const` or `new`, so `throw const Gone()` reads as the
/// class it raises.
String _thrown(Expression expression) {
  final source = expression.toSource();
  final call = source.indexOf('(');
  final named = call == -1 ? source : source.substring(0, call);
  return named.replaceFirst(RegExp(r'^(const|new)\s+'), '').trim();
}

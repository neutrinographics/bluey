import '../architecture_rule.dart';
import '../source_tree.dart';

/// Holds each root of new code to an `analysis_options.yaml` that turns on
/// the lints it must keep, so a lint switched off there fails the build
/// rather than going unnoticed.
final class LintOptionsRule implements ArchitectureRule {
  /// The rule for the folders [roots], each of which must turn on every one
  /// of [lints] once it holds Dart.
  const LintOptionsRule({required this.roots, required this.lints});

  /// The folders, package-relative, that need their own options file.
  final List<String> roots;

  /// The lints each options file must turn on.
  final Set<String> lints;

  @override
  String get name => 'lint options';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final root in roots)
      if (_holdsDart(tree, root)) ..._judge(tree, root),
  ];

  bool _holdsDart(SourceTree tree, String root) =>
      tree.withExtension('.dart').any((file) => file.path.startsWith('$root/'));

  List<Violation> _judge(SourceTree tree, String root) {
    final options = tree.file('$root/analysis_options.yaml');
    if (options == null) return [Violation(root, 'no analysis_options.yaml')];
    return [
      for (final lint in lints)
        if (!_turnsOn(options.content, lint))
          Violation(options.path, 'does not turn on $lint'),
    ];
  }

  /// Whether [options] holds an uncommented list item naming [lint], the
  /// form a rule takes under `linter: rules:`.
  bool _turnsOn(String options, String lint) {
    final item = RegExp('^\\s*-\\s*${RegExp.escape(lint)}\\s*(#.*)?\$');
    return options.split('\n').any((line) => item.hasMatch(line.trimRight()));
  }
}

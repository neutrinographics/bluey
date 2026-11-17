import 'package:yaml/yaml.dart';

import '../architecture_rule.dart';
import '../source_file.dart';
import '../source_tree.dart';

/// Holds each root of new code to an `analysis_options.yaml` that turns on
/// the lints it must keep, and every options file beneath it to keeping
/// them on, so a lint switched off anywhere under a root fails the build
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

  /// The root's own options file, then every deeper one in path order. A
  /// deeper file replaces the root's for the folder it sits in, so it must
  /// turn the lints on itself.
  List<Violation> _judge(SourceTree tree, String root) {
    final own = '$root/analysis_options.yaml';
    final deeper = [
      for (final file in tree.withExtension('.yaml'))
        if (file.path.startsWith('$root/') &&
            file.path.endsWith('/analysis_options.yaml') &&
            file.path != own)
          file,
    ];
    return [
      if (tree.file(own) case final options?)
        ..._judgeFile(options)
      else
        Violation(root, 'no analysis_options.yaml'),
      for (final options in deeper) ..._judgeFile(options),
    ];
  }

  List<Violation> _judgeFile(SourceFile options) {
    final Object? yaml;
    try {
      yaml = loadYaml(options.content);
    } on YamlException {
      return [Violation(options.path, 'does not parse as YAML')];
    }
    return [
      for (final lint in lints)
        if (!_turnsOn(yaml, lint))
          Violation(options.path, 'does not turn on $lint'),
      for (final lint in lints)
        if (_ignores(yaml, lint))
          Violation(options.path, 'sets $lint to ignore'),
    ];
  }

  /// Whether `linter: rules:` names [lint] as a list item, or maps it to
  /// `true`.
  bool _turnsOn(Object? options, String lint) => switch (options) {
    {'linter': {'rules': final List<Object?> rules}} => rules.contains(lint),
    {'linter': {'rules': final Map<Object?, Object?> rules}} =>
      rules[lint] == true,
    _ => false,
  };

  /// Whether `analyzer: errors:` turns [lint]'s diagnostics off, which
  /// silences it however the rules turn it on.
  bool _ignores(Object? options, String lint) => switch (options) {
    {'analyzer': {'errors': final Map<Object?, Object?> errors}} =>
      errors[lint] == 'ignore',
    _ => false,
  };
}

import '../architecture_rule.dart';
import '../dart_source.dart';
import '../placement.dart';
import '../source_tree.dart';
import 'rule_support.dart';

/// Holds the contexts and the kernel to answering a failure as a value, so
/// the only errors that leave placed code are the programming errors that
/// mean a bug.
///
/// An entry names a file and a raise with a count and no line, so an edit
/// above a raise never rewrites the list, and the count may fall and never
/// rise.
final class ThrowsRule implements MeasuringRule, WeighingRule {
  /// The rule, where [programmingErrors] are the classes placed code may
  /// throw.
  const ThrowsRule({required this.programmingErrors});

  /// The classes whose throw means a bug (`StateError`, `ArgumentError`),
  /// each allowed with any of its named constructors.
  final Set<String> programmingErrors;

  @override
  String get name => 'throws';

  @override
  List<Violation> check(SourceTree tree) => [
    for (final source in tree.dartSources)
      if (libraryPlacement(source.path) case InFeature() || InShared())
        for (final MapEntry(key: what, value: count)
            in _countsOf(source).entries)
          Violation(source.path, '$what, ${_times(count)}'),
  ];

  /// A throws entry owes its raises in one file, so a file that raises one
  /// fewer owes less and one that raises one more owes more.
  @override
  Debt weigh(String entry) => switch (_Counted.parse(entry)) {
    final counted? => (debt: counted.debt, amount: counted.count),
    null => (debt: entry, amount: 1),
  };

  /// Answer a raise that grew as a value, and lower the entry of one that
  /// fell, so the message never reads as an invitation to raise a count.
  @override
  String? change({required String known, required String found}) {
    final (was, now) = (_Counted.parse(known), _Counted.parse(found));
    if (was == null || now == null || was.debt != now.debt) return null;
    final raises = '${now.path} raises ${now.what} ${_times(now.count)}';
    return now.count > was.count
        ? '$raises, up from ${was.count}: answer the new one as a value; '
            'never raise the entry'
        : '$raises, down from ${was.count}: lower its entry to '
            '${_times(now.count)}';
  }

  /// The raises of [source] that are not programming errors, each counted,
  /// in the order each first appears.
  Map<String, int> _countsOf(DartSource source) {
    final counts = <String, int>{};
    for (final raise in source.raises) {
      if (_isProgrammingError(raise)) continue;
      counts.update(raise.what, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  bool _isProgrammingError(Raise raise) {
    if (!raise.what.startsWith('throw ')) return false;
    final thrown = raise.what.substring('throw '.length);
    return programmingErrors.any(
      (error) => thrown == error || thrown.startsWith('$error.'),
    );
  }
}

String _times(int count) => count == 1 ? '1 time' : '$count times';

/// A throws entry, `path -> raise, N times`, read back into its parts.
final class _Counted {
  _Counted(this.path, this.what, this.count);

  static final _shape = RegExp(r'^(.+?) -> (.+), (\d+) times?$');

  static _Counted? parse(String entry) {
    if (_shape.firstMatch(entry)?.groups([1, 2, 3]) case [
      final path?,
      final what?,
      final count?,
    ]) {
      return _Counted(path, what, int.parse(count));
    }
    return null;
  }

  final String path;
  final String what;
  final int count;

  String get debt => '$path -> $what';
}

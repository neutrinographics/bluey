import 'package:bluey_guards/architecture.dart';
import 'package:bluey_guards/gates.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bluey_architecture.dart';

const _path = 'test/architecture/known_violations.dart';

/// Bluey's lists as the file holds them today, with [list] changed by
/// [change], so each case judges a change to the real lists by the real
/// rules' weights, as the Lists only shrink job does, or, when [weighed] is
/// false, entry by entry, as a gate that knew no rule would.
ListGrowth _growthAfter(
  String list,
  List<String> Function(List<String> entries) change, {
  bool weighed = true,
}) {
  final base = readKnownViolations();
  return ListGrowth.between(
    path: _path,
    base: base,
    head: {...base, list: change(base[list] ?? const [])},
    weights: weighed ? weightsOf(blueyRules) : const {},
  );
}

/// The first entry of Bluey's [list] today that [pick] reads, with what it
/// reads from it, so a case judges an entry the list really holds and fails,
/// rather than passing over nothing, once the list holds none.
(String, T) _listed<T extends Object>(
  String list,
  T? Function(String entry) pick,
) {
  for (final entry in readKnownViolations()[list] ?? const <String>[]) {
    if (pick(entry) case final picked?) return (entry, picked);
  }
  fail('$list holds no entry this case can judge: retire the case');
}

final _intoTodaysContext = RegExp(
  r'^(.+) -> lib/src/(connection|discovery|gatt_client|gatt_server|peer|'
  r'platform)/(?:.+/)?([^/]+\.dart)$',
);

/// A boundaries entry into a context's folder of today, rewritten to the
/// same file at its place in the target layout.
String? _movedToItsPlace(String entry) {
  if (_intoTodaysContext.firstMatch(entry)?.groups([1, 2, 3]) case [
    final source?,
    final context?,
    final file?,
  ]) {
    return '$source -> lib/src/features/$context/domain/$file';
  }
  return null;
}

/// Another entry of Bluey's boundaries today from [entry]'s source into the
/// same context, with it rewritten to its place, or null when it has none.
(String, String)? _secondIntoTheSameContext(String entry) {
  final context = _intoTodaysContext.firstMatch(entry)?.group(2);
  if (context == null) return null;
  final source = entry.split(' -> ').first;
  for (final other in readKnownViolations()['boundaries'] ?? const []) {
    if (other != entry && other.startsWith('$source -> lib/src/$context/')) {
      if (_movedToItsPlace(other) case final moved?) return (other, moved);
    }
  }
  return null;
}

final _sized = RegExp(r'^(.+) -> (\d+) lines$');

/// A size entry lowered by one line, as it is rewritten when its file
/// shrinks.
String? _loweredByOne(String entry) {
  if (_sized.firstMatch(entry)?.groups([1, 2]) case [
    final path?,
    final lines?,
  ]) {
    return '$path -> ${int.parse(lines) - 1} lines';
  }
  return null;
}

List<String> Function(List<String>) _rewriting(String from, String to) =>
    (entries) => [for (final entry in entries) entry == from ? to : entry];

/// Bluey's lists as the file holds them today, with the throws list
/// [atBase] at the base and [atHead] at the head, since the list is empty
/// today and a change to it needs an entry at the base.
ListGrowth _throwsGrowth(List<String> atBase, List<String> atHead) {
  final lists = readKnownViolations();
  return ListGrowth.between(
    path: _path,
    base: {...lists, 'throws': atBase},
    head: {...lists, 'throws': atHead},
    weights: weightsOf(blueyRules),
  );
}

const _raising = 'lib/src/features/connection/application/connect_device.dart';

void main() {
  group("Bluey's lists judged by its rules' weights", () {
    test('a boundaries entry whose target moved to its place in the target '
        'layout holds, which a gate that knew no rule would refuse', () {
      // arrange
      final (entry, moved) = _listed('boundaries', _movedToItsPlace);

      // act
      final growth = _growthAfter('boundaries', _rewriting(entry, moved));
      final unweighed = _growthAfter(
        'boundaries',
        _rewriting(entry, moved),
        weighed: false,
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
      expect(unweighed.holds, isFalse);
    });

    test('a boundaries entry into a context its source did not depend on '
        'grows the list', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          ...entries,
          'lib/src/gatt_client/gatt.dart -> lib/src/peer/server_id.dart',
        ],
      );

      // assert
      expect(growth.added, [
        'boundaries: lib/src/gatt_client/gatt.dart -> '
            'lib/src/peer/server_id.dart',
      ]);
    });

    test('a second boundaries entry into a context its source depended on '
        'grows the list', () {
      // act
      final growth = _growthAfter(
        'boundaries',
        (entries) => [
          ...entries,
          'lib/src/shared/exceptions.dart -> '
              'lib/src/features/platform/domain/capabilities.dart',
        ],
      );

      // assert
      expect(growth.raised, [
        'boundaries: lib/src/shared/exceptions.dart into platform, 1 at '
            'the base and 2 at the head: '
            'lib/src/shared/exceptions.dart -> '
            'lib/src/features/platform/domain/capabilities.dart',
      ]);
    });

    test('of two boundaries entries from one source into one context, the '
        'one whose target moved into shared is deleted and the other '
        'rewritten to its place, and the list holds, which a gate that knew '
        'no rule would refuse', () {
      // arrange
      final (intoShared, (other, moved)) = _listed(
        'boundaries',
        _secondIntoTheSameContext,
      );
      List<String> change(List<String> entries) => [
        for (final entry in entries)
          if (entry == other) moved else if (entry != intoShared) entry,
      ];

      // act
      final growth = _growthAfter('boundaries', change);
      final unweighed = _growthAfter('boundaries', change, weighed: false);

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
      expect(unweighed.added, ['boundaries: $moved']);
    });

    test("an oversized entry lowered to its file's new length holds, which "
        'a gate that knew no rule would refuse', () {
      // arrange
      final (entry, lowered) = _listed('oversized', _loweredByOne);

      // act
      final growth = _growthAfter('oversized', _rewriting(entry, lowered));
      final unweighed = _growthAfter(
        'oversized',
        _rewriting(entry, lowered),
        weighed: false,
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
      expect(unweighed.holds, isFalse);
    });

    test('a throws entry whose count fell holds', () {
      // act
      final growth = _throwsGrowth(
        ['$_raising -> throw Gone, 2 times'],
        ['$_raising -> throw Gone, 1 time'],
      );

      // assert
      expect(growth.holds, isTrue, reason: growth.describe());
    });

    test('a throws entry whose count rose grows the list', () {
      // act
      final growth = _throwsGrowth(
        ['$_raising -> throw Gone, 2 times'],
        ['$_raising -> throw Gone, 3 times'],
      );

      // assert
      expect(growth.raised, [
        'throws: $_raising -> throw Gone, 2 at the base and 3 at the head: '
            '$_raising -> throw Gone, 3 times',
      ]);
    });
  });
}

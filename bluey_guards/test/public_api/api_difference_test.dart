import 'package:bluey_guards/public_api.dart';
import 'package:test/test.dart';

const _committed = '''
class A
  String toString()
  int get size
class B
  String toString()
''';

void main() {
  group('ApiDifference', () {
    test('is empty for the same text', () {
      // arrange
      const current = _committed;

      // act
      final difference = ApiDifference.between(
        committed: _committed,
        current: current,
      );

      // assert
      expect(difference.isEmpty, isTrue);
    });

    test(
      'sees a member leave one declaration though another keeps the same line',
      () {
        // arrange
        const current = '''
class A
  int get size
class B
  String toString()
''';

        // act
        final difference = ApiDifference.between(
          committed: _committed,
          current: current,
        );

        // assert
        expect(difference.removed, ['class A > String toString()']);
        expect(difference.added, isEmpty);
      },
    );

    test('names a new declaration and each of its members', () {
      // arrange
      const current = '''
${_committed}class C
  C()
''';

      // act
      final difference = ApiDifference.between(
        committed: _committed,
        current: current,
      );

      // assert
      expect(difference.added, ['class C', 'class C > C()']);
      expect(difference.isEmpty, isFalse);
    });
  });
}

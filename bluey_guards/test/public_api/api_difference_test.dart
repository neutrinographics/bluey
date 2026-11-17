import 'package:bluey_guards/public_api.dart';
import 'package:test/test.dart';

const _committed =
    'class A\n  String toString()\n  int get size\nclass B\n  String toString()\n';

void main() {
  group('ApiDifference', () {
    test('is empty for the same text', () {
      // act
      final difference = ApiDifference.between(
        committed: _committed,
        current: _committed,
      );

      // assert
      expect(difference.isEmpty, isTrue);
    });

    test(
      'sees a member leave one declaration though another keeps the same line',
      () {
        // act
        final difference = ApiDifference.between(
          committed: _committed,
          current: 'class A\n  int get size\nclass B\n  String toString()\n',
        );

        // assert
        expect(difference.removed, ['class A > String toString()']);
        expect(difference.added, isEmpty);
      },
    );

    test('names a new declaration and each of its members', () {
      // act
      final difference = ApiDifference.between(
        committed: _committed,
        current: '${_committed}class C\n  C()\n',
      );

      // assert
      expect(difference.added, ['class C', 'class C > C()']);
      expect(difference.isEmpty, isFalse);
    });
  });
}

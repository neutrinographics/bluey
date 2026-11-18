import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkId', () {
    test('two ids with the same value are equal', () {
      // arrange
      final value = 'L${1}';

      // act
      final first = LinkId(value);
      final second = LinkId(value);

      // assert
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('two ids with different values differ', () {
      // arrange
      const first = LinkId('L1');

      // act
      const second = LinkId('L2');

      // assert
      expect(first, isNot(second));
    });
  });
}

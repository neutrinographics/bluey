import 'package:bluey_guards/architecture.dart';
import 'package:test/test.dart';

void main() {
  group('weightsOf', () {
    test("names each weighing rule's list with how it weighs an entry", () {
      // arrange
      final rules = <String, ArchitectureRule>{
        'oversized': SizeRule(limit: 300, extension: '.dart'),
        'publicExports': const PublicExportsRule(package: 'held'),
      };

      // act
      final weights = weightsOf(rules);

      // assert
      expect(weights.keys, ['oversized']);
      expect(weights['oversized']?.call('lib/a.dart -> 420 lines'), (
        debt: 'lib/a.dart',
        amount: 420,
      ));
    });
  });
}

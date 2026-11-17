import 'package:bluey_guards/gates.dart';
import 'package:test/test.dart';

void main() {
  group('declaresCodeThatRuns', () {
    final nothingRuns = {
      'an enum of plain values': '''
enum ScanState { stopped, scanning }
''',
      'an interface of abstract members': '''
abstract interface class Failure {
  String get message;
  Future<void> write(List<int> value, {bool withResponse = true});
}
''',
      'exports only': '''
library;

export 'src/a.dart';
export 'src/b.dart' show B;
''',
      'a typedef and a constant': '''
typedef Handler = void Function(int);
const limit = 300;
''',
    };
    for (final MapEntry(key: shape, value: source) in nothingRuns.entries) {
      test('is false for $shape', () {
        // act
        final runs = declaresCodeThatRuns(source);

        // assert
        expect(runs, isFalse);
      });
    }

    final somethingRuns = {
      'a method with a body': '''
abstract class Scanner {
  void stop() {}
}
''',
      'a getter written as an expression': '''
abstract class Scanner {
  bool get isScanning => false;
}
''',
      'an enum with a member': '''
enum Phy {
  le1m;

  bool get isFast => this != le1m;
}
''',
      'a constructor, even a const one with no body': '''
final class Mtu {
  const Mtu(this.value);
  final int value;
}
''',
      'a field initialized when an instance is made': '''
final class Registry {
  final entries = <int>[];
}
''',
      'a top-level variable initialized when it is first read': '''
final started = DateTime.now();
''',
      'a top-level function': '''
int twice(int value) => value * 2;
''',
      'an extension type, even one with no members': '''
extension type ServerId(String value) {}
''',
    };
    for (final MapEntry(key: shape, value: source) in somethingRuns.entries) {
      test('is true for $shape', () {
        // act
        final runs = declaresCodeThatRuns(source);

        // assert
        expect(runs, isTrue);
      });
    }
  });

  group('unreportedFiles', () {
    test('names each file with code that runs that the report lacks', () {
      // arrange
      final coverage = LineCoverage.parse(
        'SF:lib/src/measured.dart\nLF:2\nLH:2\nend_of_record\n',
      );
      final sources = {
        'lib/src/measured.dart': 'int one() => 1;',
        'lib/src/unloaded.dart': 'int two() => 2;',
        'lib/src/state.dart': 'enum State { on, off }',
      };

      // act
      final unreported = unreportedFiles(sources, coverage);

      // assert
      expect(unreported, ['lib/src/unloaded.dart']);
    });

    test('names them in path order', () {
      // arrange
      final coverage = LineCoverage.parse('');
      final sources = {
        'lib/src/z.dart': 'int z() => 1;',
        'lib/a.dart': 'int a() => 1;',
      };

      // act
      final unreported = unreportedFiles(sources, coverage);

      // assert
      expect(unreported, ['lib/a.dart', 'lib/src/z.dart']);
    });
  });
}

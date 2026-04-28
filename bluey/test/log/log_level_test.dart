import 'package:bluey/src/log/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlueyLogLevel', () {
    test('declares trace, debug, info, warn, error in ascending severity', () {
      expect(BlueyLogLevel.values, [
        BlueyLogLevel.trace,
        BlueyLogLevel.debug,
        BlueyLogLevel.info,
        BlueyLogLevel.warn,
        BlueyLogLevel.error,
      ]);
    });

    test('index reflects semantic ordering for filtering', () {
      expect(BlueyLogLevel.trace.index, lessThan(BlueyLogLevel.debug.index));
      expect(BlueyLogLevel.debug.index, lessThan(BlueyLogLevel.info.index));
      expect(BlueyLogLevel.info.index, lessThan(BlueyLogLevel.warn.index));
      expect(BlueyLogLevel.warn.index, lessThan(BlueyLogLevel.error.index));
    });
  });
}

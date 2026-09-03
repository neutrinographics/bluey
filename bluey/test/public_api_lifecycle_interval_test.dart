import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `Bluey.server` docs tell consumers to compare against
/// `LifecycleInterval.minimum`; that only holds if the value object is
/// reachable through the public barrel, not a `src/` import.
void main() {
  test('LifecycleInterval is part of the public API', () {
    expect(LifecycleInterval.minimum, greaterThan(Duration.zero));
    expect(
      LifecycleInterval(const Duration(seconds: 10)),
      equals(LifecycleInterval.standard),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/domain/recovery_notifier.dart';

void main() {
  group('RecoveryNotifier', () {
    test('initial tick is zero', () {
      final notifier = RecoveryNotifier();
      expect(notifier.value, equals(0));
    });

    test('notify() increments tick', () {
      final notifier = RecoveryNotifier();
      notifier.notify();
      notifier.notify();
      expect(notifier.value, equals(2));
    });

    test('listeners fire on notify', () {
      final notifier = RecoveryNotifier();
      var fired = 0;
      notifier.addListener(() => fired++);
      notifier.notify();
      notifier.notify();
      expect(fired, equals(2));
    });
  });
}

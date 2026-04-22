import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/presentation/stress_tests_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StressTestsState.initial', () {
    test('contains one card per StressTest enum value', () {
      final s = StressTestsState.initial();
      expect(s.cards.keys, equals(StressTest.values.toSet()));
    });

    test('each initial card has its default config and no result', () {
      final s = StressTestsState.initial();
      expect(s.cards[StressTest.burstWrite]!.config, isA<BurstWriteConfig>());
      expect(s.cards[StressTest.burstWrite]!.result, isNull);
      expect(s.cards[StressTest.burstWrite]!.isRunning, isFalse);
    });

    test('anyRunning is false initially', () {
      expect(StressTestsState.initial().anyRunning, isFalse);
    });
  });

  group('StressTestsState.updateCard', () {
    test('replaces only the named card', () {
      final s = StressTestsState.initial();
      final updated = s.updateCard(
        StressTest.burstWrite,
        s.cards[StressTest.burstWrite]!.copyWith(isRunning: true),
      );
      expect(updated.cards[StressTest.burstWrite]!.isRunning, isTrue);
      expect(updated.cards[StressTest.mixedOps]!.isRunning, isFalse);
      expect(updated.anyRunning, isTrue);
    });
  });

  group('TestCardState.copyWith', () {
    final base = TestCardState(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 10)),
      isRunning: true,
    );

    test('copyWith without passing result PRESERVES the existing result', () {
      final copy = base.copyWith(isRunning: false);
      expect(copy.result, isNotNull,
          reason:
              'The existing result must not be erased by an unrelated copyWith.');
      expect(copy.isRunning, isFalse);
    });

    test('copyWith can explicitly clear result by passing null', () {
      final copy = base.copyWith(result: null);
      expect(copy.result, isNull);
    });

    test('copyWith can replace result', () {
      final newResult = StressTestResult.initial();
      final copy = base.copyWith(result: newResult);
      expect(identical(copy.result, newResult), isTrue);
    });

    test('copyWith can update config', () {
      final copy = base.copyWith(config: const BurstWriteConfig(count: 999));
      expect((copy.config as BurstWriteConfig).count, equals(999));
    });
  });
}

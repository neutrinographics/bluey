import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/stress_tests/application/run_burst_write.dart';
import 'package:bluey_example/features/stress_tests/application/run_mixed_ops.dart';
import 'package:bluey_example/features/stress_tests/application/run_soak.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/presentation/stress_tests_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRunBurstWrite extends Mock implements RunBurstWrite {}

class _MockRunMixedOps extends Mock implements RunMixedOps {}

class _MockRunSoak extends Mock implements RunSoak {}

class _MockConnection extends Mock implements Connection {}

class _FakeConnection extends Fake implements Connection {}

void main() {
  late _MockRunBurstWrite mockRun;
  late _MockRunMixedOps mockRunMixedOps;
  late _MockRunSoak mockRunSoak;
  late _MockConnection mockConn;

  setUpAll(() {
    registerFallbackValue(const BurstWriteConfig());
    registerFallbackValue(_FakeConnection());
  });

  setUp(() {
    mockRun = _MockRunBurstWrite();
    mockRunMixedOps = _MockRunMixedOps();
    mockRunSoak = _MockRunSoak();
    mockConn = _MockConnection();
  });

  StressTestsCubit makeCubit() => StressTestsCubit(
        runBurstWrite: mockRun,
        runMixedOps: mockRunMixedOps,
        runSoak: mockRunSoak,
        connection: mockConn,
      );

  group('StressTestsCubit.run', () {
    test('emits cards updated as the runner emits results', () async {
      final controller = StreamController<StressTestResult>();
      when(() => mockRun.call(any(), any()))
          .thenAnswer((_) => controller.stream);

      final cubit = makeCubit();
      final sub = cubit.stream.listen((_) {});

      cubit.run(StressTest.burstWrite);
      controller.add(StressTestResult.initial());
      await Future<void>.delayed(Duration.zero);
      controller.add(StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 1))
          .finished(elapsed: const Duration(milliseconds: 1)));
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.cards[StressTest.burstWrite]!.isRunning, isFalse);
      expect(cubit.state.cards[StressTest.burstWrite]!.result, isNotNull);
      await sub.cancel();
      await cubit.close();
    });

    test('is a no-op when another card is already running', () async {
      final controller = StreamController<StressTestResult>();
      when(() => mockRun.call(any(), any()))
          .thenAnswer((_) => controller.stream);

      final cubit = makeCubit();
      cubit.run(StressTest.burstWrite);
      // Second run while first is pending: should be ignored.
      cubit.run(StressTest.mixedOps);

      expect(cubit.state.cards[StressTest.mixedOps]!.isRunning, isFalse);
      await controller.close();
      await cubit.close();
    });
  });

  group('StressTestsCubit.stop', () {
    test('clears isRunning for the active card', () async {
      final controller = StreamController<StressTestResult>();
      when(() => mockRun.call(any(), any()))
          .thenAnswer((_) => controller.stream);

      final cubit = makeCubit();
      cubit.run(StressTest.burstWrite);
      expect(cubit.state.cards[StressTest.burstWrite]!.isRunning, isTrue);

      cubit.stop();
      expect(cubit.state.cards[StressTest.burstWrite]!.isRunning, isFalse);

      await controller.close();
      await cubit.close();
    });

    test('preserves the result when stopping mid-run', () async {
      // This test would have caught the copyWith-clears-result bug.
      final controller = StreamController<StressTestResult>();
      when(() => mockRun.call(any(), any()))
          .thenAnswer((_) => controller.stream);

      final cubit = makeCubit();
      cubit.run(StressTest.burstWrite);
      controller.add(StressTestResult.initial()
          .recordSuccess(latency: const Duration(milliseconds: 5)));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.cards[StressTest.burstWrite]!.result, isNotNull);

      cubit.stop();
      expect(cubit.state.cards[StressTest.burstWrite]!.result, isNotNull,
          reason: 'stop() must not erase the intermediate result snapshot');

      await controller.close();
      await cubit.close();
    });
  });

  group('StressTestsCubit.updateConfig', () {
    test('updates the card config when idle', () {
      final cubit = makeCubit();
      cubit.updateConfig(
        StressTest.burstWrite,
        const BurstWriteConfig(count: 42),
      );
      final cfg =
          cubit.state.cards[StressTest.burstWrite]!.config as BurstWriteConfig;
      expect(cfg.count, equals(42));
    });

    test('is a no-op while the card is running', () async {
      final controller = StreamController<StressTestResult>();
      when(() => mockRun.call(any(), any()))
          .thenAnswer((_) => controller.stream);

      final cubit = makeCubit();
      cubit.run(StressTest.burstWrite);
      cubit.updateConfig(
        StressTest.burstWrite,
        const BurstWriteConfig(count: 999),
      );
      final cfg =
          cubit.state.cards[StressTest.burstWrite]!.config as BurstWriteConfig;
      expect(cfg.count, equals(50), reason: 'default count, update ignored');

      await controller.close();
      await cubit.close();
    });
  });
}

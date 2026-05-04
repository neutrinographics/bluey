import 'package:equatable/equatable.dart';

import '../domain/stress_test.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';

const Object _absent = Object();

/// One per StressTest enum value. Holds the per-card UI state.
class TestCardState extends Equatable {
  final StressTest test;
  final StressTestConfig config;
  final StressTestResult? result;
  final bool isRunning;

  const TestCardState({
    required this.test,
    required this.config,
    this.result,
    this.isRunning = false,
  });

  TestCardState copyWith({
    StressTestConfig? config,
    Object? result = _absent,
    bool? isRunning,
  }) {
    return TestCardState(
      test: test,
      config: config ?? this.config,
      result:
          identical(result, _absent)
              ? this.result
              : result as StressTestResult?,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  List<Object?> get props => [test, config, result, isRunning];
}

class StressTestsState extends Equatable {
  final Map<StressTest, TestCardState> cards;

  /// True when ANY card is running; used to disable other cards' Run buttons.
  bool get anyRunning => cards.values.any((c) => c.isRunning);

  const StressTestsState({required this.cards});

  factory StressTestsState.initial() {
    return StressTestsState(
      cards: {
        StressTest.burstWrite: const TestCardState(
          test: StressTest.burstWrite,
          config: BurstWriteConfig(),
        ),
        StressTest.mixedOps: const TestCardState(
          test: StressTest.mixedOps,
          config: MixedOpsConfig(),
        ),
        StressTest.soak: const TestCardState(
          test: StressTest.soak,
          config: SoakConfig(),
        ),
        StressTest.timeoutProbe: const TestCardState(
          test: StressTest.timeoutProbe,
          config: TimeoutProbeConfig(),
        ),
        StressTest.failureInjection: const TestCardState(
          test: StressTest.failureInjection,
          config: FailureInjectionConfig(),
        ),
        StressTest.mtuProbe: const TestCardState(
          test: StressTest.mtuProbe,
          config: MtuProbeConfig(),
        ),
        StressTest.notificationThroughput: const TestCardState(
          test: StressTest.notificationThroughput,
          config: NotificationThroughputConfig(),
        ),
      },
    );
  }

  StressTestsState updateCard(StressTest test, TestCardState newState) {
    return StressTestsState(
      cards: {
        for (final entry in cards.entries)
          entry.key: entry.key == test ? newState : entry.value,
      },
    );
  }

  @override
  List<Object?> get props => [cards];
}

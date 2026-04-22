import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/run_burst_write.dart';
import '../application/run_failure_injection.dart';
import '../application/run_mixed_ops.dart';
import '../application/run_soak.dart';
import '../application/run_timeout_probe.dart';
import '../domain/stress_test.dart';
import '../domain/stress_test_config.dart';
import '../domain/stress_test_result.dart';
import 'stress_tests_state.dart';

class StressTestsCubit extends Cubit<StressTestsState> {
  final RunBurstWrite _runBurstWrite;
  final RunMixedOps _runMixedOps;
  final RunSoak _runSoak;
  final RunTimeoutProbe _runTimeoutProbe;
  final RunFailureInjection _runFailureInjection;
  final Connection _connection;
  StreamSubscription<StressTestResult>? _activeSub;

  StressTestsCubit({
    required RunBurstWrite runBurstWrite,
    required RunMixedOps runMixedOps,
    required RunSoak runSoak,
    required RunTimeoutProbe runTimeoutProbe,
    required RunFailureInjection runFailureInjection,
    required Connection connection,
  })  : _runBurstWrite = runBurstWrite,
        _runMixedOps = runMixedOps,
        _runSoak = runSoak,
        _runTimeoutProbe = runTimeoutProbe,
        _runFailureInjection = runFailureInjection,
        _connection = connection,
        super(StressTestsState.initial());

  /// Updates the config form for a card. Ignored while the card is running.
  void updateConfig(StressTest test, StressTestConfig config) {
    final card = state.cards[test]!;
    if (card.isRunning) return;
    emit(state.updateCard(test, card.copyWith(config: config)));
  }

  /// Kicks off the test for [test]. No-op if any other card is already
  /// running.
  void run(StressTest test) {
    if (state.anyRunning) return;
    final card = state.cards[test]!;
    emit(state.updateCard(test, card.copyWith(isRunning: true)));

    final Stream<StressTestResult> stream = switch (test) {
      StressTest.burstWrite =>
        _runBurstWrite(card.config as BurstWriteConfig, _connection),
      StressTest.mixedOps =>
        _runMixedOps(card.config as MixedOpsConfig, _connection),
      StressTest.soak =>
        _runSoak(card.config as SoakConfig, _connection),
      StressTest.timeoutProbe =>
        _runTimeoutProbe(card.config as TimeoutProbeConfig, _connection),
      StressTest.failureInjection =>
        _runFailureInjection(card.config as FailureInjectionConfig, _connection),
      _ => Stream<StressTestResult>.error(
          UnimplementedError('Test $test not yet wired'),
        ),
    };

    _activeSub = stream.listen(
      (StressTestResult result) {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(
            result: result,
            isRunning: result.isRunning,
          ),
        ));
      },
      onDone: () {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(isRunning: false),
        ));
      },
      onError: (Object e) {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(isRunning: false),
        ));
      },
    );
  }

  /// Cancels the current run. Background ops complete uncounted; the
  /// next run's Reset prologue cleans up server state.
  void stop() {
    _activeSub?.cancel();
    _activeSub = null;
    final running = state.cards.values.where((c) => c.isRunning).toList();
    for (final r in running) {
      emit(state.updateCard(r.test, r.copyWith(isRunning: false)));
    }
  }

  @override
  Future<void> close() {
    _activeSub?.cancel();
    return super.close();
  }
}

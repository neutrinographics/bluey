import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/run_burst_write.dart';
import '../domain/stress_test.dart';
import '../domain/stress_test_config.dart';
import 'stress_tests_state.dart';

class StressTestsCubit extends Cubit<StressTestsState> {
  final RunBurstWrite _runBurstWrite;
  final Connection _connection;
  StreamSubscription<dynamic>? _activeSub;

  StressTestsCubit({
    required RunBurstWrite runBurstWrite,
    required Connection connection,
  })  : _runBurstWrite = runBurstWrite,
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
  Future<void> run(StressTest test) async {
    if (state.anyRunning) return;
    final card = state.cards[test]!;
    emit(state.updateCard(test, card.copyWith(isRunning: true)));

    final Stream<dynamic> stream = switch (test) {
      StressTest.burstWrite =>
        _runBurstWrite(card.config as BurstWriteConfig, _connection),
      _ => Stream<dynamic>.error(
          UnimplementedError('Test $test not yet wired'),
        ),
    };

    _activeSub = stream.listen(
      (dynamic result) {
        emit(state.updateCard(
          test,
          state.cards[test]!.copyWith(
            result: result as dynamic,
            isRunning: (result as dynamic).isRunning as bool,
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

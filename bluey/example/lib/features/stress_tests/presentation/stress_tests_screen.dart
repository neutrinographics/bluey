import 'package:bluey/bluey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/di/service_locator.dart';
import '../application/run_burst_write.dart';
import 'stress_tests_cubit.dart';
import 'stress_tests_state.dart';
import 'widgets/test_card.dart';

class StressTestsScreen extends StatelessWidget {
  final Connection connection;
  const StressTestsScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StressTestsCubit(
        runBurstWrite: getIt<RunBurstWrite>(),
        connection: connection,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Stress Tests')),
        body: BlocBuilder<StressTestsCubit, StressTestsState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final entry in state.cards.entries)
                  TestCard(
                    test: entry.key,
                    config: entry.value.config,
                    result: entry.value.result,
                    isRunning: entry.value.isRunning,
                    anyRunning: state.anyRunning,
                    onRun: () =>
                        context.read<StressTestsCubit>().run(entry.key),
                    onStop: () => context.read<StressTestsCubit>().stop(),
                    onConfigChanged: (cfg) => context
                        .read<StressTestsCubit>()
                        .updateConfig(entry.key, cfg),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

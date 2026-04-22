import 'package:bluey/bluey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/di/service_locator.dart';
import '../application/run_burst_write.dart';
import 'stress_tests_cubit.dart';
import 'stress_tests_state.dart';

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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${state.cards.length} tests configured'),
                  const SizedBox(height: 8),
                  Text(
                    state.anyRunning ? 'A test is running' : 'Idle',
                    style: TextStyle(
                      color: state.anyRunning ? Colors.orange : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_result.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/test_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Idle card shows test name and enabled Run/Stop buttons', (tester) async {
    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: null,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.text('Burst write'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('Run button is disabled when another card is running', (tester) async {
    var ran = false;
    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: null,
      isRunning: false,
      anyRunning: true,
      onRun: () => ran = true,
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    // Tapping the disabled Run button must not fire onRun.
    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(ran, isFalse,
        reason: 'Run should be no-op when another card runs');
  });

  testWidgets('Results panel renders attempted/succeeded/failed when result present', (tester) async {
    final result = StressTestResult.initial()
        .recordSuccess(latency: const Duration(milliseconds: 10))
        .recordFailure(typeName: 'GattTimeoutException')
        .finished(elapsed: const Duration(seconds: 2));

    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: result,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.textContaining('Attempted 2'), findsOneWidget);
    expect(find.textContaining('Succeeded 1'), findsOneWidget);
    expect(find.textContaining('Failed 1'), findsOneWidget);
    expect(find.textContaining('GattTimeoutException'), findsOneWidget);
  });

  testWidgets('Results panel shows Connection lost banner when connectionLost is true', (tester) async {
    final result = StressTestResult.initial()
        .recordSuccess(latency: const Duration(milliseconds: 10))
        .markConnectionLost()
        .recordFailure(typeName: 'DisconnectedException');

    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: result,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.text('Connection lost'), findsOneWidget);
  });

  testWidgets('Results panel does NOT show Connection lost banner when flag is false', (tester) async {
    final result = StressTestResult.initial()
        .recordSuccess(latency: const Duration(milliseconds: 10))
        .finished(elapsed: const Duration(seconds: 1));

    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: result,
      isRunning: false,
      anyRunning: false,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    expect(find.text('Connection lost'), findsNothing);
  });

  testWidgets('Config form is disabled while running', (tester) async {
    await tester.pumpWidget(wrap(TestCard(
      test: StressTest.burstWrite,
      config: const BurstWriteConfig(),
      result: null,
      isRunning: true,
      anyRunning: true,
      onRun: () {},
      onStop: () {},
      onConfigChanged: (_) {},
    )));

    // Text fields should be disabled when the card is running.
    final countField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'count',
    );
    expect(countField, findsOneWidget);
    expect(tester.widget<TextField>(countField).enabled, isFalse);
  });
}

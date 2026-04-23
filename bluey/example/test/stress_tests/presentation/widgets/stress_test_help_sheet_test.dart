import 'package:bluey_example/features/stress_tests/domain/stress_test.dart';
import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/stress_test_help_sheet.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/test_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StressTestConfig _defaultConfig(StressTest test) => switch (test) {
      StressTest.burstWrite => const BurstWriteConfig(),
      StressTest.mixedOps => const MixedOpsConfig(),
      StressTest.soak => const SoakConfig(),
      StressTest.timeoutProbe => const TimeoutProbeConfig(),
      StressTest.failureInjection => const FailureInjectionConfig(),
      StressTest.mtuProbe => const MtuProbeConfig(),
      StressTest.notificationThroughput => const NotificationThroughputConfig(),
    };

void main() {
  Widget wrapSheet(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  group('StressTestHelpSheet', () {
    for (final test in StressTest.values) {
      testWidgets('renders display name for ${test.name}', (tester) async {
        await tester.pumpWidget(
          wrapSheet(StressTestHelpSheet(test: test)),
        );
        expect(find.text(test.displayName), findsOneWidget);
      });
    }

    testWidgets('shows WHAT IT DOES section label', (tester) async {
      await tester.pumpWidget(
        wrapSheet(StressTestHelpSheet(test: StressTest.burstWrite)),
      );
      expect(find.text('WHAT IT DOES'), findsOneWidget);
    });

    testWidgets('shows READING THE RESULTS section label', (tester) async {
      await tester.pumpWidget(
        wrapSheet(StressTestHelpSheet(test: StressTest.burstWrite)),
      );
      expect(find.text('READING THE RESULTS'), findsOneWidget);
    });
  });

  group('TestCard info button', () {
    testWidgets('info button is present on each card', (tester) async {
      for (final test in StressTest.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TestCard(
                  test: test,
                  config: _defaultConfig(test),
                  result: null,
                  isRunning: false,
                  anyRunning: false,
                  onRun: () {},
                  onStop: () {},
                  onConfigChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('i'),
          findsOneWidget,
          reason: 'Expected info button on ${test.name} card',
        );
      }
    });

    testWidgets('tapping info button opens help sheet with correct content',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TestCard(
                test: StressTest.burstWrite,
                config: const BurstWriteConfig(),
                result: null,
                isRunning: false,
                anyRunning: false,
                onRun: () {},
                onStop: () {},
                onConfigChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();

      expect(find.byType(StressTestHelpSheet), findsOneWidget);
      expect(find.text('WHAT IT DOES'), findsOneWidget);
      expect(find.text('READING THE RESULTS'), findsOneWidget);
    });

    testWidgets('help sheet is dismissible by tapping barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TestCard(
                test: StressTest.mixedOps,
                config: const MixedOpsConfig(),
                result: null,
                isRunning: false,
                anyRunning: false,
                onRun: () {},
                onStop: () {},
                onConfigChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.byType(StressTestHelpSheet), findsOneWidget);

      // Tap the modal barrier above the sheet to dismiss it.
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.byType(StressTestHelpSheet), findsNothing);
    });
  });
}

import 'package:bluey_example/features/stress_tests/presentation/widgets/tolerance_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('ToleranceIndicator', () {
    testWidgets('renders Strict label for value 1', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(maxFailedHeartbeats: 1)),
      );
      expect(find.text('Tolerance: Strict'), findsOneWidget);
    });

    testWidgets('renders Tolerant label for value 3', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(maxFailedHeartbeats: 3)),
      );
      expect(find.text('Tolerance: Tolerant'), findsOneWidget);
    });

    testWidgets('renders Very tolerant label for value 5', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(maxFailedHeartbeats: 5)),
      );
      expect(find.text('Tolerance: Very tolerant'), findsOneWidget);
    });

    testWidgets('renders raw number for non-named value', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(maxFailedHeartbeats: 7)),
      );
      expect(find.text('Tolerance: 7'), findsOneWidget);
    });
  });
}

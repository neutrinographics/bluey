import 'package:bluey_example/features/stress_tests/presentation/widgets/tolerance_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('ToleranceIndicator', () {
    testWidgets('renders Strict label for 10 s', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(
            peerSilenceTimeout: Duration(seconds: 10))),
      );
      expect(find.text('Tolerance: Strict'), findsOneWidget);
    });

    testWidgets('renders Tolerant label for 30 s', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(
            peerSilenceTimeout: Duration(seconds: 30))),
      );
      expect(find.text('Tolerance: Tolerant'), findsOneWidget);
    });

    testWidgets('renders Very tolerant label for 60 s', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(
            peerSilenceTimeout: Duration(seconds: 60))),
      );
      expect(find.text('Tolerance: Very tolerant'), findsOneWidget);
    });

    testWidgets('renders raw seconds for non-named value', (tester) async {
      await tester.pumpWidget(
        wrap(const ToleranceIndicator(
            peerSilenceTimeout: Duration(seconds: 7))),
      );
      expect(find.text('Tolerance: 7s'), findsOneWidget);
    });
  });
}

import 'package:bluey_example/features/connection/presentation/connection_settings_cubit.dart';
import 'package:bluey_example/features/connection/presentation/widgets/tolerance_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child, ConnectionSettingsCubit cubit) {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<ConnectionSettingsCubit>.value(
          value: cubit,
          child: child,
        ),
      ),
    );
  }

  group('ToleranceControl', () {
    testWidgets('renders three labelled segments', (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      expect(find.text('Strict'), findsOneWidget);
      expect(find.text('Tolerant'), findsOneWidget);
      expect(find.text('Very tolerant'), findsOneWidget);
    });

    testWidgets('default state has Strict selected (maxFailedHeartbeats=1)',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      // Default is 1 (Strict). Tap Strict — should be a no-op since it's
      // already selected.
      await tester.tap(find.text('Strict'));
      await tester.pump();
      expect(cubit.state.maxFailedHeartbeats, 1);
    });

    testWidgets('tapping Tolerant dispatches setMaxFailedHeartbeats(3)',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      await tester.tap(find.text('Tolerant'));
      await tester.pump();

      expect(cubit.state.maxFailedHeartbeats, 3);
    });

    testWidgets('tapping Very tolerant dispatches setMaxFailedHeartbeats(5)',
        (tester) async {
      final cubit = ConnectionSettingsCubit();
      await tester.pumpWidget(wrap(const ToleranceControl(), cubit));

      await tester.tap(find.text('Very tolerant'));
      await tester.pump();

      expect(cubit.state.maxFailedHeartbeats, 5);
    });
  });
}

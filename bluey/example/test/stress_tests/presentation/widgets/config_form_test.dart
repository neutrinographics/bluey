import 'package:bluey_example/features/stress_tests/domain/stress_test_config.dart';
import 'package:bluey_example/features/stress_tests/presentation/widgets/config_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('ConfigForm renders BurstWriteConfig fields', (tester) async {
    await tester.pumpWidget(wrap(ConfigForm(
      config: const BurstWriteConfig(count: 10, payloadBytes: 20),
      enabled: true,
      onChanged: (_) {},
    )));

    expect(find.text('10'), findsWidgets);
    expect(find.text('20'), findsWidgets);
  });

  testWidgets(
      'ConfigForm controller text updates when config changes without creating a new controller',
      (tester) async {
    var currentConfig = const BurstWriteConfig(count: 10, payloadBytes: 20);

    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ConfigForm(
                config: currentConfig,
                enabled: true,
                onChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );

    // Find the TextEditingControllers currently attached to 'count' field.
    // The field labeled 'count' should show '10'.
    expect(find.widgetWithText(TextField, '10'), findsOneWidget);

    // Rebuild with a new count value.
    rebuild(() {
      currentConfig = const BurstWriteConfig(count: 99, payloadBytes: 20);
    });
    await tester.pump();

    // The field should now show '99' (controller text updated in place).
    expect(find.widgetWithText(TextField, '99'), findsOneWidget);
    // The unchanged field should still show '20'.
    expect(find.widgetWithText(TextField, '20'), findsOneWidget);
  });

  testWidgets(
      'ConfigForm controllers are not recreated when rebuilt with unchanged values',
      (tester) async {
    var currentConfig = const BurstWriteConfig(count: 5, payloadBytes: 10);

    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ConfigForm(
                config: currentConfig,
                enabled: true,
                onChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );

    // Collect the controller instances before rebuild.
    final fieldsBefore = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller)
        .toList();

    // Rebuild with the same config (no value change).
    rebuild(() {});
    await tester.pump();

    final fieldsAfter = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller)
        .toList();

    // Controllers should be the same instances (not recreated).
    expect(fieldsAfter.length, equals(fieldsBefore.length));
    for (var i = 0; i < fieldsBefore.length; i++) {
      expect(fieldsAfter[i], same(fieldsBefore[i]),
          reason: 'controller at index $i should not be recreated on rebuild');
    }
  });
}

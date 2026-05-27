import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/presentation/adapter_cycle_hint.dart';

void main() {
  testWidgets('renders the hint text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdapterCycleHint()),
    ));

    expect(
      find.textContaining('toggle Bluetooth in system settings'),
      findsOneWidget,
    );
  });
}

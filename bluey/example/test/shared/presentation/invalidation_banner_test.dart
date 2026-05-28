// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_example/shared/presentation/invalidation_banner.dart';

void main() {
  testWidgets('renders label and action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(onRecover: () {}),
      ),
    ));

    expect(find.text('Bluetooth was cycled. Tap to recover.'), findsOneWidget);
    expect(find.text('Recover'), findsOneWidget);
  });

  testWidgets('calls onRecover when action tapped', (tester) async {
    var called = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(onRecover: () => called++),
      ),
    ));

    await tester.tap(find.text('Recover'));
    expect(called, equals(1));
  });

  testWidgets('honours custom label and action label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InvalidationBanner(
          label: 'Custom label',
          actionLabel: 'Retry',
          onRecover: () {},
        ),
      ),
    ));

    expect(find.text('Custom label'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

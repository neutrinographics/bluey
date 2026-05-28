import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_example/shared/presentation/bluetooth_state_chip.dart';

void main() {
  Future<void> pumpChip(WidgetTester tester, AdvertisingState state) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdvertisingStateChip(advertisingState: state),
      ),
    ));
  }

  testWidgets('idle renders "Idle"', (tester) async {
    await pumpChip(tester, AdvertisingState.idle);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('starting renders "Starting"', (tester) async {
    await pumpChip(tester, AdvertisingState.starting);
    expect(find.text('Starting'), findsOneWidget);
  });

  testWidgets('advertising renders "Advertising"', (tester) async {
    await pumpChip(tester, AdvertisingState.advertising);
    expect(find.text('Advertising'), findsOneWidget);
  });

  testWidgets('stopping renders "Stopping"', (tester) async {
    await pumpChip(tester, AdvertisingState.stopping);
    expect(find.text('Stopping'), findsOneWidget);
  });

  testWidgets('invalidated renders "Invalidated"', (tester) async {
    await pumpChip(tester, AdvertisingState.invalidated);
    expect(find.text('Invalidated'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import 'package:bluey_example/features/scanner/presentation/scanner_screen.dart';
import 'package:bluey_example/shared/di/service_locator.dart';

import '../fakes/fake_bluey_platform_for_example.dart';

void main() {
  late FakeBlueyPlatformForExample fakePlatform;

  setUp(() async {
    fakePlatform = FakeBlueyPlatformForExample();
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    await setupServiceLocator(localIdentity: ServerId.generate());
  });

  tearDown(() async {
    await fakePlatform.dispose();
    await resetServiceLocator();
  });

  testWidgets('scanner survives adapter cycle via Recover', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScannerScreen()));
    await tester.pumpAndSettle();

    // No banner before adapter cycle.
    expect(find.text('Recover'), findsNothing);

    // Cycle the adapter off — Scanner invalidates, banner should appear.
    fakePlatform.setState(platform.BluetoothState.off);
    await tester.pumpAndSettle();
    expect(find.text('Recover'), findsOneWidget);

    // Bring the adapter back on so create() returns; tap Recover.
    // recreateBluey() is async, so runAsync drives the event loop until the
    // future resolves, then pumpAndSettle flushes the resulting widget rebuild.
    fakePlatform.setState(platform.BluetoothState.on);
    await tester.runAsync(() async {
      await tester.tap(find.text('Recover'));
      // Yield to let the fire-and-forget recreateBluey() future complete.
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    // Banner cleared; the fresh cubit/screen is in its initial state.
    expect(find.text('Recover'), findsNothing);
  });
}

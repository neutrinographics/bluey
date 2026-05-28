import 'package:flutter_test/flutter_test.dart';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:bluey_example/shared/di/service_locator.dart';
import 'package:bluey_example/shared/domain/recovery_notifier.dart';

import '../../fakes/fake_bluey_platform_for_example.dart';

void main() {
  late FakeBlueyPlatformForExample fakePlatform;

  setUp(() async {
    fakePlatform = FakeBlueyPlatformForExample();
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    final identity = ServerId.generate();
    await setupServiceLocator(localIdentity: identity);
  });

  tearDown(() async {
    await fakePlatform.dispose();
    await resetServiceLocator();
  });

  test('recreateBluey swaps the singleton', () async {
    final before = getIt<Bluey>();
    await recreateBluey();
    final after = getIt<Bluey>();
    expect(identical(before, after), isFalse);
  });

  test('recreateBluey ticks the RecoveryNotifier', () async {
    final notifier = getIt<RecoveryNotifier>();
    final initial = notifier.value;
    await recreateBluey();
    expect(notifier.value, equals(initial + 1));
  });

  // Identity preservation is structural — `recreateBluey()` reuses the
  // `_capturedIdentity` stashed by `setupServiceLocator`, so the new
  // `Bluey` is constructed with the same `ServerId` by direct field
  // reuse. A test that read identity back off `Bluey` would either need
  // a public getter on the library (rejected — identity is owned by
  // the application) or an in-memory server fixture to observe via
  // `server.serverId`. The recovery end-to-end is covered by
  // `test/integration/adapter_cycle_recovery_test.dart`.
}

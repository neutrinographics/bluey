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

  test('recreateBluey preserves the localIdentity', () async {
    final identityBefore = getIt<Bluey>().localIdentity;
    await recreateBluey();
    final identityAfter = getIt<Bluey>().localIdentity;
    expect(identityAfter, equals(identityBefore));
  });
}

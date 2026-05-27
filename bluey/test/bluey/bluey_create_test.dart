import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  group('Bluey.create()', () {
    test('returns a Bluey whose currentState reflects the fake', () async {
      fakePlatform.setState(platform.BluetoothState.on);

      final bluey = await Bluey.create();
      addTearDown(bluey.dispose);

      expect(bluey.currentState, equals(BluetoothState.on));
    });

    test('awaits the first platform state event before returning', () async {
      // Fake's default is BluetoothState.on but the broadcast happens
      // when create() subscribes. Confirm the cache is fresh on return.
      final bluey = await Bluey.create();
      addTearDown(bluey.dispose);

      expect(bluey.currentState, isNot(equals(BluetoothState.unknown)));
    });

    test(
      'completes with unknown after the configured timeout if no state arrives',
      () async {
        fakePlatform.suppressInitialStateEmission = true;

        final bluey = await Bluey.create(
          initialStateTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(bluey.dispose);

        expect(bluey.currentState, equals(BluetoothState.unknown));
      },
    );
  });
}

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform fakePlatform;
  late Bluey bluey;

  setUp(() async {
    fakePlatform = FakeBlueyPlatform(
      capabilities: platform.Capabilities.android,
    );
    platform.BlueyPlatform.instance = fakePlatform;
    fakePlatform.setState(platform.BluetoothState.on);
    bluey = await Bluey.create();
  });

  tearDown(() async {
    await bluey.dispose();
    await fakePlatform.dispose();
  });

  group('Bluey.stateStream (Convention 2 — replay on subscribe)', () {
    test('replays current value to a new subscriber', () async {
      final received = <BluetoothState>[];
      final sub = bluey.stateStream.listen(received.add);

      // Give the onListen replay a microtask turn to fire.
      await Future<void>.delayed(Duration.zero);

      expect(received, equals([BluetoothState.on]));

      await sub.cancel();
    });

    test('two subscribers each get the current value independently', () async {
      final received1 = <BluetoothState>[];
      final received2 = <BluetoothState>[];

      final sub1 = bluey.stateStream.listen(received1.add);
      await Future<void>.delayed(Duration.zero);
      final sub2 = bluey.stateStream.listen(received2.add);
      await Future<void>.delayed(Duration.zero);

      expect(received1, equals([BluetoothState.on]));
      expect(received2, equals([BluetoothState.on]));

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}

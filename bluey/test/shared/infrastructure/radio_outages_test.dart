import 'dart:async';

import 'package:bluey/src/shared/domain/radio_outage.dart';
import 'package:bluey/src/shared/infrastructure/radio_outages.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';

void main() {
  late FakeBlueyPlatform platform;
  late List<RadioOutage> outages;
  late StreamSubscription<RadioOutage> subscription;

  setUp(() {
    platform = FakeBlueyPlatform();
    outages = [];
    subscription = radioOutagesOf(platform).listen(outages.add);
  });

  tearDown(() => subscription.cancel());

  for (final (state, outage) in [
    (BluetoothState.off, RadioOutage.off),
    (BluetoothState.unauthorized, RadioOutage.unauthorized),
    (BluetoothState.unsupported, RadioOutage.unsupported),
    (BluetoothState.unknown, RadioOutage.unknown),
  ]) {
    test('$state is the outage $outage', () async {
      // arrange: the subscription in setUp
      // act
      platform.setBluetoothState(state);
      await pumpEventQueue();

      // assert
      expect(outages, [outage]);
    });
  }

  test('the adapter being on is no outage', () async {
    // arrange: the subscription in setUp
    // act
    platform.setBluetoothState(BluetoothState.on);
    await pumpEventQueue();

    // assert
    expect(outages, isEmpty);
  });

  test('an error on the state stream is an unknown outage', () async {
    // arrange: the subscription in setUp
    // act
    platform.simulateStateError(StateError('lost'));
    await pumpEventQueue();

    // assert
    expect(outages, [RadioOutage.unknown]);
  });
}

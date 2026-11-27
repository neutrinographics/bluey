import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';

/// A fake that counts who listens to the adapter's state, the one stream a
/// radio scan session listens to as soon as it is built.
final class _CountingPlatform extends FakeBlueyPlatform {
  int stateListens = 0;

  @override
  Stream<platform.BluetoothState> get stateStream {
    stateListens++;
    return super.stateStream;
  }
}

void main() {
  test('a Bluey that never scanned builds no radio scan, not even to '
      'dispose it', () async {
    // arrange
    final fake = _CountingPlatform();
    platform.BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    final beforeDispose = fake.stateListens;

    // act
    await bluey.dispose();

    // assert
    expect(fake.stateListens, beforeDispose);
    await fake.dispose();
  });
}

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';

/// A fake that counts scans, to show a disposed Bluey starts none.
final class _CountingPlatform extends FakeBlueyPlatform {
  int scans = 0;

  @override
  Stream<platform.PlatformDevice> scan(platform.PlatformScanConfig config) {
    scans++;
    return super.scan(config);
  }
}

void main() {
  test('a Bluey disposed before it scanned refuses scanner() and never '
      'scans', () async {
    // arrange
    final fake = _CountingPlatform();
    platform.BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();

    // act
    await bluey.dispose();

    // assert
    expect(() => bluey.scanner(), throwsStateError);
    expect(fake.scans, 0);
    await fake.dispose();
  });
}

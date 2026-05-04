import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformAdvertiseConfig.scanResponseServiceUuids', () {
    test('defaults to empty list when not provided', () {
      const config = PlatformAdvertiseConfig(serviceUuids: ['svc-1']);
      expect(config.scanResponseServiceUuids, isEmpty);
    });

    test('preserves explicitly-supplied scan-response UUIDs', () {
      const config = PlatformAdvertiseConfig(
        serviceUuids: ['svc-1'],
        scanResponseServiceUuids: ['scan-1', 'scan-2'],
      );
      expect(config.scanResponseServiceUuids, equals(['scan-1', 'scan-2']));
    });
  });
}

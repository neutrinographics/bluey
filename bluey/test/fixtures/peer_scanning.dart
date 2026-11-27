import 'package:bluey/src/api/discovery/discovery_assembly.dart';
import 'package:bluey/src/features/discovery/infrastructure/adapters/platform_scanning.dart';
import 'package:bluey/src/peer/peer_discovery.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;

import '../fakes/test_helpers.dart';
import 'shared/application/recording_event_publisher.dart';

/// What `Bluey` hands peer discovery over [platformApi]: Discovery's scan
/// function, so a test's peers are heard the way an app's are.
DevicesAdvertising devicesAdvertisingOn(platform.BlueyPlatform platformApi) {
  final logger = testLogger();
  return DiscoveryAssembly(
    scanning: PlatformScanning(
      platformApi,
      log: logger,
      now: () => DateTime.utc(2026, 11, 27),
    ),
    publisher: RecordingEventPublisher(),
    log: logger,
    now: () => DateTime.utc(2026, 11, 27),
  ).devicesAdvertising;
}

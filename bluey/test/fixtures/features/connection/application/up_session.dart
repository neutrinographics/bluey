import 'package:bluey/src/features/connection/application/link_session.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/application/recording_log.dart';
import '../recording_link_events.dart';
import 'ports/in_memory_links.dart';

/// A session over an up link to [device], for the units that run on one;
/// its own lines go to a log of their own, so a unit's test reads only the
/// unit's lines.
Future<LinkSession> upSession(InMemoryLinks links, DeviceAddress device) async {
  links.reach(device);
  final id = (await links.open(
    device,
  )).fold((failure) => fail('the open failed: $failure'), (id) => id);
  final at = DateTime.utc(2026, 11, 26, 10);
  return LinkSession.begin(
    device: device,
    links: links,
    events: RecordingLinkEvents(),
    log: RecordingLog(),
    now: () => at,
  )..opened(id);
}

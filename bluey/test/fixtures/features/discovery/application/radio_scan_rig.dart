import 'package:bluey/src/features/discovery/application/open_scan.dart';
import 'package:bluey/src/features/discovery/application/radio_scan_session.dart';
import 'package:bluey/src/features/discovery/domain/advertisement.dart';
import 'package:bluey/src/features/discovery/domain/device.dart';
import 'package:bluey/src/features/discovery/domain/scan_ask.dart';
import 'package:bluey/src/features/discovery/domain/scan_filter.dart';
import 'package:bluey/src/features/discovery/domain/scan_result.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey/src/shared/domain/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/application/recording_log.dart';
import 'ports/in_memory_scanning.dart';
import 'ports/recording_scan_events.dart';

/// The instant every input of a [RadioScanRig] is stamped with.
final rigInstant = DateTime.utc(2026, 11, 27, 9);

final heart = UUID.short(0x180D);
final battery = UUID.short(0x180F);

/// A scan of [services], or of everything when none are given.
ScanAsk askFor([List<UUID> services = const [], Duration? timeLimit]) =>
    ScanAsk(filter: ScanFilter.of(services), timeLimit: timeLimit);

/// The scan [answer] opened, failing the test when it was refused.
OpenScan opened(Either<Object, OpenScan> answer) => answer.fold(
  (refusal) => fail('the scan was refused: $refusal'),
  (scan) => scan,
);

/// A device heard advertising [services].
ScanResult advertising(
  List<UUID> services, {
  String address = 'AA:BB:CC:DD:EE:01',
}) => ScanResult(
  device: Device(address: DeviceAddress(address)),
  rssi: -60,
  advertisement: Advertisement(
    serviceUuids: services,
    serviceData: const {},
    isConnectable: true,
  ),
  lastSeen: rigInstant,
);

/// A [RadioScanSession] over the in-memory radio, with what it raised and
/// logged kept for the test to read.
final class RadioScanRig {
  RadioScanRig({InMemoryScanning? scanning})
    : scanning = scanning ?? InMemoryScanning() {
    session = RadioScanSession(
      scanning: this.scanning,
      events: events,
      log: log,
      now: () => rigInstant,
    );
  }

  final InMemoryScanning scanning;
  final RecordingScanEvents events = RecordingScanEvents();
  final RecordingLog log = RecordingLog();
  late final RadioScanSession session;
}

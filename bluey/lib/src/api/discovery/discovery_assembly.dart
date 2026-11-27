import 'dart:async';

import '../../features/discovery/application/ports/scanning.dart';
import '../../features/discovery/application/radio_scan_session.dart';
import '../../features/discovery/domain/scan_ask.dart';
import '../../features/discovery/domain/scan_filter.dart';
import '../../features/discovery/domain/scan_phase.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/application/log.dart';
import '../../shared/application/now.dart';
import '../../shared/domain/device_address.dart';
import '../../shared/domain/either.dart';
import '../../shared/domain/uuid.dart';
import 'published_scanner.dart';
import 'scan_failure_translation.dart';
import 'scan_event_translation.dart';
import 'scanner.dart';

/// Discovery as the edge uses it: one radio scan session per `Bluey`, over
/// the [Scanning] the composition root hands it, and each scanner an app asks
/// for presented as one public [Scanner].
///
/// Every scanner it hands out shares the one session, so an app's scanners
/// widen the radio's scan between them instead of replacing each other's.
final class DiscoveryAssembly {
  /// Builds Discovery over [scanning], announcing its events on [publisher]
  /// stamped by [now].
  DiscoveryAssembly({
    required Scanning scanning,
    required EventPublisher publisher,
    required Log log,
    required Now now,
  }) : _session = RadioScanSession(
         scanning: scanning,
         events: PublishedScanEvents(publisher),
         log: log,
         now: now,
       );

  final RadioScanSession _session;

  /// A new scanner, idle. A [StateError] once this is disposed.
  Scanner scanner() => PublishedScanner(_session.openScanner());

  /// Devices heard advertising [service], on a scanner of its own so an
  /// outage that loses an app's scanners leaves the next listen unharmed.
  ///
  /// Cancelling leaves the scan and closes the scanner; a scan that fails
  /// adds its exception, and one that the radio's outage ends just closes.
  Stream<DeviceAddress> devicesAdvertising(UUID service) async* {
    final scanner = _session.openScanner();
    try {
      final opened = scanner.scan(ScanAsk(filter: ScanFilter.of([service])));
      if (opened case Right(:final value)) {
        try {
          yield* value.results.map((result) => result.device.address);
        } finally {
          value.leave();
        }
        if (await value.ended case EndedByFailure(:final failure)) {
          throw scanFailureAsException(failure);
        }
      }
    } finally {
      unawaited(scanner.close());
    }
  }

  /// Ends every scan and closes every scanner, and answers once the radio has
  /// stopped, so a disposed `Bluey` leaves no scan running and hears nothing
  /// more from the platform.
  Future<void> dispose() => _session.dispose();
}

import '../../features/discovery/application/ports/scanning.dart';
import '../../features/discovery/application/radio_scan_session.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/application/log.dart';
import '../../shared/application/now.dart';
import 'published_scanner.dart';
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

  /// Ends every scan and closes every scanner, and answers once the radio has
  /// stopped, so a disposed `Bluey` leaves no scan running and hears nothing
  /// more from the platform.
  Future<void> dispose() => _session.dispose();
}

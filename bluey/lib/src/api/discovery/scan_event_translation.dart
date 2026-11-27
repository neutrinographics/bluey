import '../../features/discovery/application/ports/scan_events.dart';
import '../../features/discovery/domain/scan_ask.dart';
import '../../features/discovery/domain/scan_event.dart';
import '../../features/discovery/domain/scan_filter.dart';
import '../../features/discovery/domain/scan_phase.dart';
import '../../shared/application/event_publisher.dart';
import '../../shared/domain/bluey_event.dart';
import '../../shared/domain/uuid.dart';
import 'scan_events.dart';

/// The source every scanner's lifecycle events have always named, so an app
/// filtering `bluey.events` by it keeps finding them.
const _source = 'BlueyScanner';

/// Publishes what the radio scan raised as the events an app reads on
/// `bluey.events`, with the fields and source they always had and the
/// instant the domain stamped as their timestamp.
///
/// A scanner stopped by an outage publishes nothing, since an app learns of
/// that from the scanner turning invalidated; a scan that ended publishes
/// nothing, since its scanner's stop says it.
final class PublishedScanEvents implements ScanEvents {
  PublishedScanEvents(this._publisher);

  final EventPublisher _publisher;

  @override
  void raise(ScanEvent event) {
    final published = _publicOf(event);
    if (published != null) _publisher.emit(published);
  }

  static BlueyEvent? _publicOf(ScanEvent event) => switch (event) {
    ScannerBeganStarting(:final ask, :final at) => ScanStartingEvent(
      serviceFilter: _servicesOf(ask),
      timeout: ask.timeLimit,
      timestamp: at,
      source: _source,
    ),
    ScannerStarted(:final ask, :final at) => ScanStartedEvent(
      serviceFilter: _servicesOf(ask),
      timeout: ask.timeLimit,
      timestamp: at,
      source: _source,
    ),
    ScannerBeganStopping(:final at) => ScanStoppingEvent(
      timestamp: at,
      source: _source,
    ),
    ScannerStopped(end: EndedByRadioOutage()) => null,
    ScannerStopped(:final at) => ScanStoppedEvent(
      timestamp: at,
      source: _source,
    ),
    ResultDelivered(:final result, :final at) => DeviceDiscoveredEvent(
      deviceAddress: result.device.address,
      name: result.device.name,
      rssi: result.rssi,
      timestamp: at,
    ),
    ScanEnded() => null,
  };

  static List<UUID>? _servicesOf(ScanAsk ask) => switch (ask.filter) {
    Everything() => null,
    ServicesOnly(:final services) => List.unmodifiable(services),
  };
}

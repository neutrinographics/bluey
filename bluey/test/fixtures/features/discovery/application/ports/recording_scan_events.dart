import 'package:bluey/src/features/discovery/application/ports/scan_events.dart';
import 'package:bluey/src/features/discovery/domain/scan_event.dart';

/// Keeps every event raised, in order, so a test reads what was published.
class RecordingScanEvents implements ScanEvents {
  final List<ScanEvent> _raised = [];

  List<ScanEvent> get raised => List.unmodifiable(_raised);

  @override
  void raise(ScanEvent event) => _raised.add(event);
}

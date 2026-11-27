import '../../domain/scan_event.dart';

/// Where Discovery's application layer hands the events its domain raised,
/// so publishing them stays the edge's business and the domain never learns
/// who listens.
abstract interface class ScanEvents {
  void raise(ScanEvent event);
}

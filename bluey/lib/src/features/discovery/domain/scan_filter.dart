import 'package:meta/meta.dart';

import '../../../shared/domain/uuid.dart';
import 'advertisement.dart';

/// Which advertisements a scan is interested in.
///
/// Scans share one radio, so the radio must cover the union of what every
/// open scan asks; each scan then keeps only what its own filter [shows].
@immutable
sealed class ScanFilter {
  const ScanFilter();

  /// Everything when [services] is null or empty, so an app that names no
  /// service is never read as asking for nothing.
  factory ScanFilter.of(Iterable<UUID>? services) {
    if (services == null) return const Everything();
    final distinct = Set<UUID>.unmodifiable(services);
    return distinct.isEmpty ? const Everything() : ServicesOnly._(distinct);
  }

  /// What a radio must cover to serve both this filter and [other].
  ScanFilter union(ScanFilter other);

  /// Whether every advertisement [other] shows is shown by this filter too,
  /// which is what lets an open scan serve a later one without the radio
  /// being restarted.
  bool covers(ScanFilter other);

  /// Whether a scan with this filter reports [advertisement].
  bool shows(Advertisement advertisement);
}

/// Every advertisement, whatever services it lists.
final class Everything extends ScanFilter {
  const Everything();

  @override
  ScanFilter union(ScanFilter other) => this;

  @override
  bool covers(ScanFilter other) => true;

  @override
  bool shows(Advertisement advertisement) => true;

  @override
  bool operator ==(Object other) => other is Everything;

  @override
  int get hashCode => (Everything).hashCode;
}

/// Only advertisements that list at least one of [services].
final class ServicesOnly extends ScanFilter {
  ServicesOnly._(this.services);

  /// The services of interest; never empty and never changed.
  final Set<UUID> services;

  @override
  ScanFilter union(ScanFilter other) => switch (other) {
    Everything() => other,
    ServicesOnly(:final services) => ServicesOnly._(
      Set<UUID>.unmodifiable({...this.services, ...services}),
    ),
  };

  @override
  bool covers(ScanFilter other) => switch (other) {
    Everything() => false,
    ServicesOnly(:final services) => this.services.containsAll(services),
  };

  @override
  bool shows(Advertisement advertisement) =>
      advertisement.serviceUuids.any(services.contains);

  @override
  bool operator ==(Object other) =>
      other is ServicesOnly &&
      other.services.length == services.length &&
      other.services.containsAll(services);

  @override
  int get hashCode => Object.hashAllUnordered(services);
}

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import 'value_objects/connection_interval.dart';
import 'value_objects/connection_parameters.dart';
import 'value_objects/peripheral_latency.dart';
import 'value_objects/supervision_timeout.dart';

/// Converts a domain [ConnectionParameters] into the wire-level
/// [PlatformConnectionParameters] DTO.
///
/// The platform interface uses primitives because it is a wire DTO.
/// Validation of BLE-spec ranges and the cross-field invariant lives
/// on the domain value object.
PlatformConnectionParameters connectionParametersToPlatform(
  ConnectionParameters params,
) {
  return PlatformConnectionParameters(
    intervalMs: params.interval.milliseconds,
    latency: params.latency.events,
    timeoutMs: params.timeout.milliseconds,
  );
}

/// Constructs a domain [ConnectionParameters] from a [PlatformConnectionParameters]
/// DTO read back from the platform.
///
/// The value object's range checks fire on construction. The platform is
/// generally authoritative, but if it reports out-of-spec values an
/// [ArgumentError] surfaces here.
ConnectionParameters connectionParametersFromPlatform(
  PlatformConnectionParameters dto,
) {
  return ConnectionParameters(
    interval: ConnectionInterval(dto.intervalMs),
    latency: PeripheralLatency(dto.latency),
    timeout: SupervisionTimeout(dto.timeoutMs),
  );
}

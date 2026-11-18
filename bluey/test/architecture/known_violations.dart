/// What the architecture rules are known to find in this package today.
///
/// A list only shrinks. An entry leaves in the commit that fixes it. An entry
/// is rewritten only for a debt that stayed or shrank: a size entry with the
/// lower count when its file shrinks, a boundaries entry with the new path
/// when its target moved within its context. No other entry is ever added,
/// and no count is ever raised: fix the code instead. docs/ARCHITECTURE.md
/// says how to read a failure.
library;

/// The library files not yet in the target layout.
const unplaced = <String>[
  'lib/src/bluey.dart -> unplaced',
  'lib/src/connection/android_connection_extensions.dart -> unplaced',
  'lib/src/connection/bluey_connection.dart -> unplaced',
  'lib/src/connection/connection.dart -> unplaced',
  'lib/src/connection/connection_parameters_mapper.dart -> unplaced',
  'lib/src/connection/ios_connection_extensions.dart -> unplaced',
  'lib/src/connection/lifecycle_client.dart -> unplaced',
  'lib/src/connection/peer_silence_monitor.dart -> unplaced',
  'lib/src/connection/value_objects/attribute_handle.dart -> unplaced',
  'lib/src/connection/value_objects/connection_interval.dart -> unplaced',
  'lib/src/connection/value_objects/connection_parameters.dart -> unplaced',
  'lib/src/connection/value_objects/mtu.dart -> unplaced',
  'lib/src/connection/value_objects/peripheral_latency.dart -> unplaced',
  'lib/src/connection/value_objects/supervision_timeout.dart -> unplaced',
  'lib/src/connection/value_objects/write_payload_limit.dart -> unplaced',
  'lib/src/discovery/advertisement.dart -> unplaced',
  'lib/src/discovery/bluey_scanner.dart -> unplaced',
  'lib/src/discovery/device.dart -> unplaced',
  'lib/src/discovery/scan.dart -> unplaced',
  'lib/src/discovery/scan_result.dart -> unplaced',
  'lib/src/discovery/scan_state.dart -> unplaced',
  'lib/src/discovery/scanner.dart -> unplaced',
  'lib/src/events.dart -> unplaced',
  'lib/src/gatt_client/gatt.dart -> unplaced',
  'lib/src/gatt_client/well_known_uuids.dart -> unplaced',
  'lib/src/gatt_server/advertising_state.dart -> unplaced',
  'lib/src/gatt_server/bluey_server.dart -> unplaced',
  'lib/src/gatt_server/client_address.dart -> unplaced',
  'lib/src/gatt_server/gatt_request.dart -> unplaced',
  'lib/src/gatt_server/hosted_gatt.dart -> unplaced',
  'lib/src/gatt_server/lifecycle_server.dart -> unplaced',
  'lib/src/gatt_server/server.dart -> unplaced',
  'lib/src/lifecycle.dart -> unplaced',
  'lib/src/peer/bluey_peer.dart -> unplaced',
  'lib/src/peer/peer.dart -> unplaced',
  'lib/src/peer/peer_client.dart -> unplaced',
  'lib/src/peer/peer_connection.dart -> unplaced',
  'lib/src/peer/peer_discovery.dart -> unplaced',
  'lib/src/peer/peer_remote_service_view.dart -> unplaced',
  'lib/src/peer/server_id.dart -> unplaced',
  'lib/src/platform/bluetooth_state.dart -> unplaced',
  'lib/src/shared/characteristic_properties.dart -> unplaced',
  'lib/src/shared/error_translation.dart -> unplaced',
  'lib/src/shared/exceptions.dart -> unplaced',
  'lib/src/shared/gatt_timeouts.dart -> unplaced',
  'lib/src/shared/manufacturer_data.dart -> unplaced',
  'lib/src/shared/uuid.dart -> unplaced',
];

/// The dependencies that cross from one context to another, or from the
/// kernel to a context.
const boundaries = <String>[
  'lib/src/connection/bluey_connection.dart -> lib/src/gatt_client/gatt.dart',
  'lib/src/connection/bluey_connection.dart -> lib/src/platform/bluetooth_state.dart',
  'lib/src/connection/connection.dart -> lib/src/gatt_client/gatt.dart',
  'lib/src/connection/lifecycle_client.dart -> lib/src/gatt_client/gatt.dart',
  'lib/src/connection/lifecycle_client.dart -> lib/src/peer/server_id.dart',
  'lib/src/discovery/bluey_scanner.dart -> lib/src/platform/bluetooth_state.dart',
  'lib/src/gatt_client/gatt.dart -> lib/src/connection/value_objects/attribute_handle.dart',
  'lib/src/gatt_server/bluey_server.dart -> lib/src/peer/peer_client.dart',
  'lib/src/gatt_server/bluey_server.dart -> lib/src/peer/server_id.dart',
  'lib/src/gatt_server/bluey_server.dart -> lib/src/platform/bluetooth_state.dart',
  'lib/src/gatt_server/lifecycle_server.dart -> lib/src/peer/server_id.dart',
  'lib/src/gatt_server/server.dart -> lib/src/peer/peer_client.dart',
  'lib/src/gatt_server/server.dart -> lib/src/peer/server_id.dart',
  'lib/src/peer/bluey_peer.dart -> lib/src/connection/bluey_connection.dart',
  'lib/src/peer/bluey_peer.dart -> lib/src/connection/lifecycle_client.dart',
  'lib/src/peer/peer_client.dart -> lib/src/gatt_server/server.dart',
  'lib/src/peer/peer_connection.dart -> lib/src/connection/connection.dart',
  'lib/src/peer/peer_connection.dart -> lib/src/connection/lifecycle_client.dart',
  'lib/src/peer/peer_connection.dart -> lib/src/gatt_client/gatt.dart',
  'lib/src/peer/peer_discovery.dart -> lib/src/connection/bluey_connection.dart',
  'lib/src/peer/peer_discovery.dart -> lib/src/connection/connection.dart',
  'lib/src/peer/peer_remote_service_view.dart -> lib/src/connection/connection.dart',
  'lib/src/peer/peer_remote_service_view.dart -> lib/src/gatt_client/gatt.dart',
  'lib/src/shared/error_translation.dart -> lib/src/connection/lifecycle_client.dart',
  'lib/src/shared/exceptions.dart -> lib/src/gatt_server/client_address.dart',
  'lib/src/shared/exceptions.dart -> lib/src/peer/server_id.dart',
  'lib/src/shared/exceptions.dart -> lib/src/platform/bluetooth_state.dart',
];

/// The files outside infrastructure that name Flutter or the platform
/// interface.
const frameworkPlacement = <String>[
  'lib/src/bluey.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/connection/bluey_connection.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/connection/connection_parameters_mapper.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/connection/lifecycle_client.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/connection/value_objects/mtu.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/discovery/bluey_scanner.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/gatt_server/bluey_server.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/gatt_server/lifecycle_server.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/lifecycle.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/peer/bluey_peer.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/peer/peer_discovery.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/shared/error_translation.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
  'lib/src/shared/error_translation.dart -> package:flutter/services.dart',
];

/// The public libraries' exports of anything but the package's own sources.
const publicExports = <String>[
  'lib/bluey.dart -> package:bluey_platform_interface/bluey_platform_interface.dart',
];

/// The placed files that point outward.
const layers = <String>[];

/// The placed files that raise anything but a programming error, each
/// entry a file and a raise with how often the file makes it, which may
/// fall and never rise.
const throws = <String>[];

/// The roots of new code whose options file leaves a required lint off.
const lintOptions = <String>[];

/// The Dart files longer than 300 lines.
const oversized = <String>[
  'lib/src/bluey.dart -> 988 lines',
  'lib/src/connection/bluey_connection.dart -> 1657 lines',
  'lib/src/connection/lifecycle_client.dart -> 836 lines',
  'lib/src/discovery/bluey_scanner.dart -> 410 lines',
  'lib/src/events.dart -> 513 lines',
  'lib/src/gatt_server/bluey_server.dart -> 1180 lines',
  'lib/src/gatt_server/lifecycle_server.dart -> 413 lines',
  'lib/src/lifecycle.dart -> 364 lines',
  'lib/src/shared/exceptions.dart -> 578 lines',
];

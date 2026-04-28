/// Bluey - A modern, elegant Bluetooth Low Energy library for Flutter
///
/// This library provides a clean, intuitive API for BLE operations following
/// Domain-Driven Design and Clean Architecture principles.
library bluey;

// Application facade
export 'src/bluey.dart';

// Shared kernel
export 'src/shared/uuid.dart';
export 'src/shared/manufacturer_data.dart';
export 'src/shared/characteristic_properties.dart';
export 'src/shared/exceptions.dart';
export 'src/shared/gatt_timeouts.dart';

// Discovery bounded context
export 'src/discovery/scanner.dart';
export 'src/discovery/device.dart';
export 'src/discovery/advertisement.dart';
export 'src/discovery/scan_result.dart';
export 'src/discovery/scan.dart';

// Connection bounded context
export 'src/connection/connection.dart';
export 'src/connection/value_objects/attribute_handle.dart';

// GATT Client bounded context
export 'src/gatt_client/gatt.dart';
export 'src/gatt_client/well_known_uuids.dart';

// GATT Server bounded context
export 'src/gatt_server/server.dart';
export 'src/gatt_server/hosted_gatt.dart';
export 'src/gatt_server/gatt_request.dart';

// Platform bounded context
export 'src/platform/bluetooth_state.dart';

// Peer bounded context
export 'src/peer/peer.dart' show BlueyPeer;
export 'src/peer/server_id.dart' show ServerId;

// Domain events
export 'src/events.dart';

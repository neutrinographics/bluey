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
export 'src/shared/domain/device_address.dart';
export 'src/shared/domain/bluey_event.dart';

// Discovery bounded context
export 'src/discovery/scanner.dart';
export 'src/discovery/device.dart';
export 'src/discovery/advertisement.dart';
export 'src/discovery/scan_result.dart';
export 'src/discovery/scan_state.dart';
export 'src/discovery/scan.dart';

// Connection bounded context
export 'src/api/connection/connection.dart';
export 'src/api/connection/android_connection_extensions.dart';
export 'src/api/connection/ios_connection_extensions.dart';
export 'src/connection/value_objects/attribute_handle.dart';

// GATT Client bounded context
export 'src/gatt_client/gatt.dart';
export 'src/gatt_client/well_known_uuids.dart';

// GATT Server bounded context
export 'src/gatt_server/server.dart';
export 'src/gatt_server/hosted_gatt.dart';
export 'src/gatt_server/gatt_request.dart';
export 'src/gatt_server/advertising_state.dart';

// Platform bounded context
export 'src/platform/bluetooth_state.dart';
export 'src/api/platform/platform.dart';

// Peer bounded context
export 'src/peer/peer.dart' show BlueyPeer;
export 'src/peer/peer_client.dart' show PeerClient;
export 'src/peer/peer_connection.dart' show PeerConnection;
export 'src/peer/server_id.dart' show ServerId;
export 'src/lifecycle.dart' show LifecycleInterval;

// Domain events
export 'src/events.dart';
export 'src/api/connection/connection_events.dart';

// Structured logging
export 'src/shared/application/log_event.dart' show BlueyLogEvent;
export 'src/shared/application/log_level.dart' show BlueyLogLevel;

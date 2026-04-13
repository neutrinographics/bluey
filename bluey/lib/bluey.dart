/// Bluey - A modern, elegant Bluetooth Low Energy library for Flutter
///
/// This library provides a clean, intuitive API for BLE operations following
/// Domain-Driven Design and Clean Architecture principles.
library bluey;

// Main entry point
export 'src/bluey.dart';

// Core value objects
export 'src/uuid.dart';
export 'src/device.dart';
export 'src/scan_result.dart';
export 'src/advertisement.dart';
export 'src/manufacturer_data.dart';
export 'src/characteristic_properties.dart';

// Scanning
export 'src/scan.dart';
export 'src/scanner.dart';

// GATT interfaces
export 'src/gatt.dart';
export 'src/connection.dart';

// Server (Peripheral role)
export 'src/server.dart';
export 'src/hosted_gatt.dart';
export 'src/gatt_request.dart';

// Well-known UUIDs
export 'src/well_known_uuids.dart';

// Exception hierarchy
export 'src/exceptions.dart';

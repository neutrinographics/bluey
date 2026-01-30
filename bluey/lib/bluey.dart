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
export 'src/characteristic_properties.dart';

// Scanning
export 'src/scan.dart';

// GATT interfaces
export 'src/gatt.dart';
export 'src/connection.dart';

// Exception hierarchy
export 'src/exceptions.dart';

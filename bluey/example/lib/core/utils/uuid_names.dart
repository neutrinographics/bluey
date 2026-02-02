import 'package:bluey/bluey.dart';

/// Utility class for mapping well-known BLE UUIDs to human-readable names.
class UuidNames {
  UuidNames._();

  /// Returns the human-readable name for a well-known service UUID,
  /// or null if the UUID is not recognized.
  static String? getServiceName(UUID uuid) {
    if (uuid == Services.genericAccess) return 'Generic Access';
    if (uuid == Services.genericAttribute) return 'Generic Attribute';
    if (uuid == Services.deviceInformation) return 'Device Information';
    if (uuid == Services.battery) return 'Battery';
    if (uuid == Services.heartRate) return 'Heart Rate';
    if (uuid == Services.healthThermometer) return 'Health Thermometer';
    if (uuid == Services.bloodPressure) return 'Blood Pressure';
    if (uuid == Services.runningSpeedAndCadence) {
      return 'Running Speed & Cadence';
    }
    if (uuid == Services.cyclingSpeedAndCadence) {
      return 'Cycling Speed & Cadence';
    }
    if (uuid == Services.cyclingPower) return 'Cycling Power';
    if (uuid == Services.locationAndNavigation) return 'Location & Navigation';
    if (uuid == Services.environmentalSensing) return 'Environmental Sensing';
    return null;
  }

  /// Returns the human-readable name for a well-known characteristic UUID,
  /// or null if the UUID is not recognized.
  static String? getCharacteristicName(UUID uuid) {
    if (uuid == Characteristics.deviceName) return 'Device Name';
    if (uuid == Characteristics.appearance) return 'Appearance';
    if (uuid == Characteristics.batteryLevel) return 'Battery Level';
    if (uuid == Characteristics.heartRateMeasurement) {
      return 'Heart Rate Measurement';
    }
    if (uuid == Characteristics.bodySensorLocation) {
      return 'Body Sensor Location';
    }
    if (uuid == Characteristics.manufacturerName) return 'Manufacturer Name';
    if (uuid == Characteristics.modelNumber) return 'Model Number';
    if (uuid == Characteristics.serialNumber) return 'Serial Number';
    if (uuid == Characteristics.firmwareRevision) return 'Firmware Revision';
    if (uuid == Characteristics.hardwareRevision) return 'Hardware Revision';
    if (uuid == Characteristics.softwareRevision) return 'Software Revision';
    return null;
  }
}

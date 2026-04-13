import '../shared/uuid.dart';

/// Standard Bluetooth SIG service UUIDs.
///
/// These are well-known 16-bit UUIDs assigned by the Bluetooth SIG.
/// See: https://www.bluetooth.com/specifications/assigned-numbers/
abstract final class Services {
  /// Generic Access Service (0x1800)
  static final genericAccess = UUID.short(0x1800);

  /// Generic Attribute Service (0x1801)
  static final genericAttribute = UUID.short(0x1801);

  /// Immediate Alert Service (0x1802)
  static final immediateAlert = UUID.short(0x1802);

  /// Link Loss Service (0x1803)
  static final linkLoss = UUID.short(0x1803);

  /// Tx Power Service (0x1804)
  static final txPower = UUID.short(0x1804);

  /// Current Time Service (0x1805)
  static final currentTime = UUID.short(0x1805);

  /// Health Thermometer Service (0x1809)
  static final healthThermometer = UUID.short(0x1809);

  /// Device Information Service (0x180A)
  static final deviceInformation = UUID.short(0x180A);

  /// Heart Rate Service (0x180D)
  static final heartRate = UUID.short(0x180D);

  /// Battery Service (0x180F)
  static final battery = UUID.short(0x180F);

  /// Blood Pressure Service (0x1810)
  static final bloodPressure = UUID.short(0x1810);

  /// Running Speed and Cadence Service (0x1814)
  static final runningSpeedAndCadence = UUID.short(0x1814);

  /// Cycling Speed and Cadence Service (0x1816)
  static final cyclingSpeedAndCadence = UUID.short(0x1816);

  /// Cycling Power Service (0x1818)
  static final cyclingPower = UUID.short(0x1818);

  /// Location and Navigation Service (0x1819)
  static final locationAndNavigation = UUID.short(0x1819);

  /// Environmental Sensing Service (0x181A)
  static final environmentalSensing = UUID.short(0x181A);

  /// Fitness Machine Service (0x1826)
  static final fitnessMachine = UUID.short(0x1826);
}

/// Standard Bluetooth SIG characteristic UUIDs.
///
/// These are well-known 16-bit UUIDs assigned by the Bluetooth SIG.
abstract final class Characteristics {
  /// Device Name (0x2A00)
  static final deviceName = UUID.short(0x2A00);

  /// Appearance (0x2A01)
  static final appearance = UUID.short(0x2A01);

  /// Battery Level (0x2A19)
  static final batteryLevel = UUID.short(0x2A19);

  /// System ID (0x2A23)
  static final systemId = UUID.short(0x2A23);

  /// Model Number String (0x2A24)
  static final modelNumber = UUID.short(0x2A24);

  /// Serial Number String (0x2A25)
  static final serialNumber = UUID.short(0x2A25);

  /// Firmware Revision String (0x2A26)
  static final firmwareRevision = UUID.short(0x2A26);

  /// Hardware Revision String (0x2A27)
  static final hardwareRevision = UUID.short(0x2A27);

  /// Software Revision String (0x2A28)
  static final softwareRevision = UUID.short(0x2A28);

  /// Manufacturer Name String (0x2A29)
  static final manufacturerName = UUID.short(0x2A29);

  /// Heart Rate Measurement (0x2A37)
  static final heartRateMeasurement = UUID.short(0x2A37);

  /// Body Sensor Location (0x2A38)
  static final bodySensorLocation = UUID.short(0x2A38);

  /// Heart Rate Control Point (0x2A39)
  static final heartRateControlPoint = UUID.short(0x2A39);

  /// Blood Pressure Measurement (0x2A35)
  static final bloodPressureMeasurement = UUID.short(0x2A35);

  /// Temperature Measurement (0x2A1C)
  static final temperatureMeasurement = UUID.short(0x2A1C);
}

/// Standard Bluetooth SIG descriptor UUIDs.
///
/// These are well-known 16-bit UUIDs assigned by the Bluetooth SIG.
abstract final class Descriptors {
  /// Characteristic Extended Properties (0x2900)
  static final characteristicExtendedProperties = UUID.short(0x2900);

  /// Characteristic User Description (0x2901)
  static final characteristicUserDescription = UUID.short(0x2901);

  /// Client Characteristic Configuration (CCCD) (0x2902)
  ///
  /// Used to enable/disable notifications and indications.
  static final clientCharacteristicConfiguration = UUID.short(0x2902);

  /// Server Characteristic Configuration (0x2903)
  static final serverCharacteristicConfiguration = UUID.short(0x2903);

  /// Characteristic Presentation Format (0x2904)
  static final characteristicPresentationFormat = UUID.short(0x2904);

  /// Characteristic Aggregate Format (0x2905)
  static final characteristicAggregateFormat = UUID.short(0x2905);
}

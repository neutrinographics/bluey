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
/// Descriptors provide metadata about their parent characteristic. Each
/// characteristic can have zero or more descriptors. The Bluetooth SIG assigns
/// well-known 16-bit UUIDs for standard descriptor types; vendors may also
/// define custom descriptors using 128-bit UUIDs.
///
/// ## Common descriptors
///
/// | UUID   | Name                             | Typical use                          |
/// |--------|----------------------------------|--------------------------------------|
/// | 0x2900 | Extended Properties              | Rarely used; flags reliable-write    |
/// | 0x2901 | User Description                 | Human-readable characteristic name   |
/// | 0x2902 | Client Characteristic Config     | Enable/disable notify or indicate    |
/// | 0x2903 | Server Characteristic Config     | Broadcast configuration              |
/// | 0x2904 | Presentation Format              | Unit, exponent, namespace of value   |
/// | 0x2905 | Aggregate Format                 | Ordered list of Presentation Formats |
///
/// ## Notes for peripheral (server) implementors
///
/// - **CCCD (0x2902)** is managed automatically by the platform stack whenever
///   you add a characteristic with `canNotify: true` or `canIndicate: true`.
///   You do not need to add it yourself via [HostedDescriptor]; doing so may
///   produce a runtime error on some platforms.
/// - **User Description (0x2901)** is the most useful descriptor to add
///   manually. Set it once using [HostedDescriptor.immutable] and the value is
///   served automatically on reads without any application-side request
///   handling.
///
/// ## Notes for central (client) implementors
///
/// - Descriptors are discovered as part of [RemoteService] and are available
///   on each [RemoteCharacteristic] via its `descriptors` list.
/// - Read descriptor values using [Connection.readDescriptor].
/// - The CCCD is written automatically by the platform when you call
///   [Connection.subscribeToCharacteristic]; you do not write it directly.
abstract final class Descriptors {
  /// Characteristic Extended Properties (0x2900)
  ///
  /// A 2-byte bit field that extends the properties declared in the
  /// characteristic declaration. Currently defines two flags:
  /// - Bit 0: Reliable Write — client may use ATT Prepare Write procedure.
  /// - Bit 1: Writable Auxiliaries — the User Description descriptor (0x2901)
  ///   on this characteristic is writable.
  ///
  /// This descriptor is rarely encountered in practice.
  static final characteristicExtendedProperties = UUID.short(0x2900);

  /// Characteristic User Description (0x2901)
  ///
  /// A UTF-8 string that provides a human-readable name for the
  /// characteristic (e.g., `"Heart Rate"`, `"Battery Level"`, `"Sensor Temp"`).
  ///
  /// **Reading:** Decode the raw bytes with `utf8.decode(bytes)`.
  ///
  /// **Writing (peripheral side):** Add this descriptor using
  /// [HostedDescriptor.immutable] with the name encoded as UTF-8 bytes:
  /// ```dart
  /// HostedDescriptor.immutable(
  ///   uuid: Descriptors.characteristicUserDescription,
  ///   value: Uint8List.fromList(utf8.encode('My Characteristic')),
  /// )
  /// ```
  ///
  /// **Writing (central side):** Only possible if the Extended Properties
  /// descriptor (0x2900) has the "Writable Auxiliaries" bit set.
  static final characteristicUserDescription = UUID.short(0x2901);

  /// Client Characteristic Configuration Descriptor (CCCD) (0x2902)
  ///
  /// A 2-byte bit field written by the central to enable or disable
  /// notifications and indications for a characteristic:
  /// - `0x0000` — disabled
  /// - `0x0001` — notifications enabled
  /// - `0x0002` — indications enabled
  ///
  /// **You do not interact with this descriptor directly.**
  ///
  /// - On the **peripheral side**, the platform adds and manages the CCCD
  ///   automatically whenever a characteristic declares `canNotify: true` or
  ///   `canIndicate: true`. Do not add a [HostedDescriptor] for 0x2902.
  /// - On the **central side**, the platform writes the CCCD automatically
  ///   when you call [Connection.subscribeToCharacteristic]. You do not need
  ///   to read or write it yourself.
  static final clientCharacteristicConfiguration = UUID.short(0x2902);

  /// Server Characteristic Configuration (0x2903)
  ///
  /// Similar to the CCCD (0x2902) but controls server-initiated broadcast
  /// rather than per-connection notifications. Only relevant for
  /// characteristics that support the "Broadcast" property, which is uncommon.
  ///
  /// Bit 0: Broadcasts enabled — characteristic value is included in
  /// advertising packets when set.
  static final serverCharacteristicConfiguration = UUID.short(0x2903);

  /// Characteristic Presentation Format (0x2904)
  ///
  /// A 7-byte structure describing how to interpret the characteristic value:
  ///
  /// | Byte(s) | Field       | Description                                   |
  /// |---------|-------------|-----------------------------------------------|
  /// | 0       | Format      | Data type (e.g., 0x04 = uint8, 0x0E = utf8s)  |
  /// | 1       | Exponent    | Signed integer; value = raw × 10^exponent     |
  /// | 2–3     | Unit        | Bluetooth SIG unit UUID (e.g., 0x2700 = m/s²) |
  /// | 4       | Namespace   | 0x01 = Bluetooth SIG                          |
  /// | 5–6     | Description | Namespace-specific description index          |
  ///
  /// Useful when a characteristic carries a numeric value whose unit and
  /// scale are not implied by its UUID (e.g., a vendor-specific sensor).
  static final characteristicPresentationFormat = UUID.short(0x2904);

  /// Characteristic Aggregate Format (0x2905)
  ///
  /// A list of attribute handles pointing to [characteristicPresentationFormat]
  /// (0x2904) descriptors on other characteristics. Allows a single
  /// characteristic to represent an ordered tuple of values, each described
  /// by its own Presentation Format descriptor.
  ///
  /// Rarely used outside of compound measurements (e.g., a multi-axis sensor
  /// reporting X, Y, Z as separate characteristics aggregated into one).
  static final characteristicAggregateFormat = UUID.short(0x2905);
}

import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

/// Common UUIDs used in tests.
class TestUuids {
  // Standard BLE Services
  static const heartRateService = '0000180d-0000-1000-8000-00805f9b34fb';
  static const batteryService = '0000180f-0000-1000-8000-00805f9b34fb';
  static const deviceInfoService = '0000180a-0000-1000-8000-00805f9b34fb';
  static const environmentalService = '0000181a-0000-1000-8000-00805f9b34fb';

  // Standard BLE Characteristics
  static const heartRateMeasurement = '00002a37-0000-1000-8000-00805f9b34fb';
  static const bodySensorLocation = '00002a38-0000-1000-8000-00805f9b34fb';
  static const batteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
  static const temperature = '00002a6e-0000-1000-8000-00805f9b34fb';
  static const humidity = '00002a6f-0000-1000-8000-00805f9b34fb';

  // Custom UUIDs for testing
  static const customService = '12345678-1234-1234-1234-123456789abc';
  static const customChar1 = '12345678-1234-1234-1234-123456789abd';
  static const customChar2 = '12345678-1234-1234-1234-123456789abe';
}

/// Common device IDs used in tests (MAC address format).
class TestDeviceIds {
  static const device1 = 'AA:BB:CC:DD:EE:01';
  static const device2 = 'AA:BB:CC:DD:EE:02';
  static const device3 = 'AA:BB:CC:DD:EE:03';
  static const central1 = 'central-1';
  static const central2 = 'central-2';
  static const central3 = 'central-3';
}

/// Builder for creating test characteristic properties.
class TestProperties {
  static const readOnly = PlatformCharacteristicProperties(
    canRead: true,
    canWrite: false,
    canWriteWithoutResponse: false,
    canNotify: false,
    canIndicate: false,
  );

  static const writeOnly = PlatformCharacteristicProperties(
    canRead: false,
    canWrite: true,
    canWriteWithoutResponse: false,
    canNotify: false,
    canIndicate: false,
  );

  static const notifyOnly = PlatformCharacteristicProperties(
    canRead: false,
    canWrite: false,
    canWriteWithoutResponse: false,
    canNotify: true,
    canIndicate: false,
  );

  static const readWrite = PlatformCharacteristicProperties(
    canRead: true,
    canWrite: true,
    canWriteWithoutResponse: false,
    canNotify: false,
    canIndicate: false,
  );

  static const readNotify = PlatformCharacteristicProperties(
    canRead: true,
    canWrite: false,
    canWriteWithoutResponse: false,
    canNotify: true,
    canIndicate: false,
  );

  static const writeWithoutResponse = PlatformCharacteristicProperties(
    canRead: false,
    canWrite: false,
    canWriteWithoutResponse: true,
    canNotify: false,
    canIndicate: false,
  );

  static const all = PlatformCharacteristicProperties(
    canRead: true,
    canWrite: true,
    canWriteWithoutResponse: true,
    canNotify: true,
    canIndicate: true,
  );
}

/// Builder for creating test services.
class TestServiceBuilder {
  final String uuid;
  final bool isPrimary;
  final List<PlatformCharacteristic> _characteristics = [];

  TestServiceBuilder(this.uuid, {this.isPrimary = true});

  /// Adds a readable characteristic.
  TestServiceBuilder withReadable(String charUuid) {
    _characteristics.add(
      PlatformCharacteristic(
        uuid: charUuid,
        properties: TestProperties.readOnly,
        descriptors: const [],
      ),
    );
    return this;
  }

  /// Adds a writable characteristic.
  TestServiceBuilder withWritable(String charUuid) {
    _characteristics.add(
      PlatformCharacteristic(
        uuid: charUuid,
        properties: TestProperties.writeOnly,
        descriptors: const [],
      ),
    );
    return this;
  }

  /// Adds a notifiable characteristic.
  TestServiceBuilder withNotifiable(String charUuid) {
    _characteristics.add(
      PlatformCharacteristic(
        uuid: charUuid,
        properties: TestProperties.notifyOnly,
        descriptors: const [],
      ),
    );
    return this;
  }

  /// Adds a read/write characteristic.
  TestServiceBuilder withReadWrite(String charUuid) {
    _characteristics.add(
      PlatformCharacteristic(
        uuid: charUuid,
        properties: TestProperties.readWrite,
        descriptors: const [],
      ),
    );
    return this;
  }

  /// Adds a custom characteristic.
  TestServiceBuilder withCharacteristic(
    String charUuid,
    PlatformCharacteristicProperties properties,
  ) {
    _characteristics.add(
      PlatformCharacteristic(
        uuid: charUuid,
        properties: properties,
        descriptors: const [],
      ),
    );
    return this;
  }

  /// Builds the service.
  PlatformService build() {
    return PlatformService(
      uuid: uuid,
      isPrimary: isPrimary,
      characteristics: _characteristics,
      includedServices: const [],
    );
  }
}

/// Helper for creating test data.
class TestData {
  /// Creates a Uint8List from a list of integers.
  static Uint8List bytes(List<int> data) => Uint8List.fromList(data);

  /// Creates an empty Uint8List.
  static Uint8List empty() => Uint8List(0);

  /// Creates a Uint8List of the specified length with sequential values.
  static Uint8List sequential(int length) =>
      Uint8List.fromList(List.generate(length, (i) => i % 256));

  /// Creates a heart rate measurement packet.
  static Uint8List heartRate(int bpm) => bytes([0x00, bpm]);

  /// Creates a battery level packet.
  static Uint8List batteryLevel(int percent) => bytes([percent]);
}

/// Scans for the first device, unwrapping the [ScanResult].
///
/// Convenience helper for integration tests that need a [Device]
/// from a scan but don't care about transient observation data.
Future<Device> scanFirstDevice(Bluey bluey) async {
  final result = await bluey.scan().first;
  return result.device;
}

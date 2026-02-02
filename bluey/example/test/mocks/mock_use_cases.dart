import 'package:mocktail/mocktail.dart';

// Scanner Use Cases
import 'package:bluey_example/scanner/domain/use_cases/scan_for_devices.dart';
import 'package:bluey_example/scanner/domain/use_cases/stop_scan.dart';
import 'package:bluey_example/scanner/domain/use_cases/get_bluetooth_state.dart';
import 'package:bluey_example/scanner/domain/use_cases/request_permissions.dart';
import 'package:bluey_example/scanner/domain/use_cases/request_enable.dart';

// Connection Use Cases
import 'package:bluey_example/connection/domain/use_cases/connect_to_device.dart';
import 'package:bluey_example/connection/domain/use_cases/disconnect_device.dart';
import 'package:bluey_example/connection/domain/use_cases/discover_services.dart';

// GATT Use Cases
import 'package:bluey_example/gatt/domain/use_cases/read_characteristic.dart';
import 'package:bluey_example/gatt/domain/use_cases/write_characteristic.dart';
import 'package:bluey_example/gatt/domain/use_cases/subscribe_to_characteristic.dart';
import 'package:bluey_example/gatt/domain/use_cases/read_descriptor.dart';

// Server Use Cases
import 'package:bluey_example/server/domain/use_cases/start_advertising.dart';
import 'package:bluey_example/server/domain/use_cases/stop_advertising.dart';
import 'package:bluey_example/server/domain/use_cases/add_service.dart';
import 'package:bluey_example/server/domain/use_cases/send_notification.dart';

// Scanner Mocks
class MockScanForDevices extends Mock implements ScanForDevices {}

class MockStopScan extends Mock implements StopScan {}

class MockGetBluetoothState extends Mock implements GetBluetoothState {}

class MockRequestPermissions extends Mock implements RequestPermissions {}

class MockRequestEnable extends Mock implements RequestEnable {}

// Connection Mocks
class MockConnectToDevice extends Mock implements ConnectToDevice {}

class MockDisconnectDevice extends Mock implements DisconnectDevice {}

class MockDiscoverServices extends Mock implements DiscoverServices {}

// GATT Mocks
class MockReadCharacteristic extends Mock implements ReadCharacteristic {}

class MockWriteCharacteristic extends Mock implements WriteCharacteristic {}

class MockSubscribeToCharacteristic extends Mock
    implements SubscribeToCharacteristic {}

class MockReadDescriptor extends Mock implements ReadDescriptor {}

// Server Mocks
class MockStartAdvertising extends Mock implements StartAdvertising {}

class MockStopAdvertising extends Mock implements StopAdvertising {}

class MockAddService extends Mock implements AddService {}

class MockSendNotification extends Mock implements SendNotification {}

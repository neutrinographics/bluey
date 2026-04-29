import 'package:mocktail/mocktail.dart';

// Scanner Use Cases
import 'package:bluey_example/features/scanner/application/scan_for_devices.dart';
import 'package:bluey_example/features/scanner/application/stop_scan.dart';
import 'package:bluey_example/features/scanner/application/get_bluetooth_state.dart';
import 'package:bluey_example/features/scanner/application/request_permissions.dart';
import 'package:bluey_example/features/scanner/application/request_enable.dart';

// Connection Use Cases
import 'package:bluey_example/features/connection/application/connect_to_device.dart';
import 'package:bluey_example/features/connection/application/disconnect_device.dart';
import 'package:bluey_example/features/connection/application/get_services.dart';
import 'package:bluey_example/features/connection/application/watch_peer.dart';

// Service Explorer Use Cases
import 'package:bluey_example/features/service_explorer/application/read_characteristic.dart';
import 'package:bluey_example/features/service_explorer/application/write_characteristic.dart';
import 'package:bluey_example/features/service_explorer/application/subscribe_to_characteristic.dart';
import 'package:bluey_example/features/service_explorer/application/read_descriptor.dart';

// Server Use Cases
import 'package:bluey_example/features/server/application/start_advertising.dart';
import 'package:bluey_example/features/server/application/stop_advertising.dart';
import 'package:bluey_example/features/server/application/add_service.dart';
import 'package:bluey_example/features/server/application/send_notification.dart';
import 'package:bluey_example/features/server/application/check_server_support.dart';
import 'package:bluey_example/features/server/application/set_server_identity.dart';
import 'package:bluey_example/features/server/application/reset_server.dart';
import 'package:bluey_example/features/server/application/observe_connections.dart';
import 'package:bluey_example/features/server/application/observe_peer_connections.dart';
import 'package:bluey_example/features/server/application/disconnect_client.dart';
import 'package:bluey_example/features/server/application/dispose_server.dart';
import 'package:bluey_example/features/server/application/get_connected_clients.dart';
import 'package:bluey_example/features/server/application/observe_disconnections.dart';
import 'package:bluey_example/features/server/application/handle_requests.dart';
import 'package:bluey_example/features/server/application/get_server.dart';
import 'package:bluey_example/features/server/infrastructure/server_identity_storage.dart';

// Scanner Mocks
class MockScanForDevices extends Mock implements ScanForDevices {}

class MockStopScan extends Mock implements StopScan {}

class MockGetBluetoothState extends Mock implements GetBluetoothState {}

class MockRequestPermissions extends Mock implements RequestPermissions {}

class MockRequestEnable extends Mock implements RequestEnable {}

// Connection Mocks
class MockConnectToDevice extends Mock implements ConnectToDevice {}

class MockDisconnectDevice extends Mock implements DisconnectDevice {}

class MockGetServices extends Mock implements GetServices {}

class MockWatchPeer extends Mock implements WatchPeer {}

// Service Explorer Mocks
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

class MockCheckServerSupport extends Mock implements CheckServerSupport {}

class MockSetServerIdentity extends Mock implements SetServerIdentity {}

class MockResetServer extends Mock implements ResetServer {}

class MockServerIdentityStorage extends Mock implements ServerIdentityStorage {}

class MockObserveConnections extends Mock implements ObserveConnections {}

class MockObservePeerConnections extends Mock
    implements ObservePeerConnections {}

class MockDisconnectClient extends Mock implements DisconnectClient {}

class MockDisposeServer extends Mock implements DisposeServer {}

class MockGetConnectedClients extends Mock implements GetConnectedClients {}

class MockObserveDisconnections extends Mock implements ObserveDisconnections {}

class MockObserveReadRequests extends Mock implements ObserveReadRequests {}

class MockObserveWriteRequests extends Mock implements ObserveWriteRequests {}

class MockGetServer extends Mock implements GetServer {}

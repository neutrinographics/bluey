import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'package:bluey/src/lifecycle.dart' show controlServiceUuid;

import '../fakes/fake_platform.dart';
import '../fakes/test_helpers.dart';

void main() {
  late FakeBlueyPlatform fake;
  late Bluey bluey;

  setUp(() async {
    fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
    bluey = await Bluey.create(localIdentity: TestServerIds.localIdentity);
  });

  tearDown(() async {
    await bluey.dispose();
  });

  test('discoverPeers while the app scans leaves the app\'s scan running and '
      'delivering', () async {
    // arrange
    final scanner = bluey.scanner();
    final heard = <String>[];
    final states = <ScanState>[];
    scanner.scan().listen((r) => heard.add(r.device.address.value));
    await pumpEventQueue();
    scanner.stateChanges.listen(states.add);
    final peerId = ServerId.generate();
    fake.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: peerId);

    // act
    final discovery = bluey.discoverPeers(
      timeout: const Duration(milliseconds: 300),
    );
    await pumpEventQueue();
    fake.simulateScanResult(_advertisingControlService('AA:BB:CC:DD:EE:01'));
    final peers = await discovery;
    await pumpEventQueue();
    fake.simulatePeripheral(
      id: 'AA:BB:CC:DD:EE:09',
      name: 'later',
      serviceUuids: const [],
    );
    await pumpEventQueue();

    // assert
    expect(peers.map((p) => p.serverId), [peerId]);
    expect(scanner.state, ScanState.scanning);
    expect(states, everyElement(ScanState.scanning));
    expect(fake.isScanning, isTrue);
    expect(heard, contains('AA:BB:CC:DD:EE:01'));
  });

  test('an app scan filtered to another service still lets discoverPeers '
      'find a peer', () async {
    // arrange
    final scanner = bluey.scanner();
    scanner
        .scan(services: [UUID('0000180d-0000-1000-8000-00805f9b34fb')])
        .listen((_) {});
    await pumpEventQueue();
    final peerId = ServerId.generate();
    fake.simulateBlueyServer(address: 'AA:BB:CC:DD:EE:01', serverId: peerId);

    // act
    final peers = await bluey.discoverPeers(
      timeout: const Duration(milliseconds: 300),
    );

    // assert
    expect(peers.map((p) => p.serverId), [peerId]);
    expect(scanner.state, ScanState.scanning);
  });
}

platform.PlatformDevice _advertisingControlService(String address) =>
    platform.PlatformDevice(
      id: address,
      name: 'Bluey Server',
      rssi: -50,
      serviceUuids: [controlServiceUuid],
      manufacturerDataCompanyId: null,
      manufacturerData: null,
    );

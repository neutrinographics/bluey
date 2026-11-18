import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_platform.dart';
import '../../fakes/test_helpers.dart';

const _heartRate = '0000180d-0000-1000-8000-00805f9b34fb';
const _measurement = '00002a37-0000-1000-8000-00805f9b34fb';

void main() {
  const address = 'AA:BB:CC:DD:EE:01';
  late FakeBlueyPlatform fake;
  late Bluey bluey;
  final device = Device(address: const DeviceAddress(address));

  setUp(() async {
    fake = FakeBlueyPlatform(capabilities: platform.Capabilities.android);
    platform.BlueyPlatform.instance = fake;
    bluey = await Bluey.create(localIdentity: TestServerIds.localIdentity);
  });

  tearDown(() => bluey.dispose());

  void simulateSensor() => fake.simulatePeripheral(
    id: address,
    services: const [
      platform.PlatformService(
        uuid: _heartRate,
        isPrimary: true,
        characteristics: [
          platform.PlatformCharacteristic(
            uuid: _measurement,
            properties: TestProperties.readWrite,
            descriptors: [],
            handle: 0,
          ),
        ],
        includedServices: [],
      ),
    ],
    characteristicValues: {
      _measurement: Uint8List.fromList([0x01]),
    },
  );

  Future<RemoteCharacteristic> measurementOf(Connection connection) async {
    final services = await connection.services();
    return services.single.characteristics().single;
  }

  group('H3 (I381): remote disconnect never finalises the Connection', () {
    test('stateChanges closes after the peer drops the link', () async {
      // arrange
      fake.simulatePeripheral(id: address);
      final connection = await bluey.connect(device);
      var done = false;
      connection.stateChanges.listen((_) {}, onDone: () => done = true);

      // act
      fake.simulateDisconnection(address);
      await pumpEventQueue();

      // assert
      expect(connection.state, ConnectionState.disconnected);
      expect(
        done,
        isTrue,
        reason: 'await-for consumers of stateChanges hang forever',
      );
    });

    test('disconnect() after a remote drop still releases resources', () async {
      // arrange
      fake.simulatePeripheral(id: address);
      final connection = await bluey.connect(device);
      var done = false;
      connection.stateChanges.listen((_) {}, onDone: () => done = true);
      fake.simulateDisconnection(address);
      await pumpEventQueue();

      // act
      await connection.disconnect();
      await pumpEventQueue();

      // assert
      expect(
        done,
        isTrue,
        reason: 'disconnect() early-returns, so cleanup can never run',
      );
    });
  });

  group('A Connection whose link the peer dropped', () {
    test('an operation after a drop fails with linkLoss', () async {
      // arrange
      simulateSensor();
      final connection = await bluey.connect(device);
      final measurement = await measurementOf(connection);
      fake.simulateDisconnection(address);
      await pumpEventQueue();

      // act
      final read = measurement.read();

      // assert
      await expectLater(
        read,
        throwsA(
          isA<DisconnectedException>()
              .having((e) => e.address, 'address', address)
              .having((e) => e.reason, 'reason', DisconnectReason.linkLoss),
        ),
      );
    });

    test(
      'an operation in flight when the peer drops fails with linkLoss at once',
      () async {
        // arrange
        simulateSensor();
        final connection = await bluey.connect(device);
        final measurement = await measurementOf(connection);
        fake.holdNextReadCharacteristic();
        Object? failure;
        measurement.read().then<void>(
          (_) {},
          onError: (Object error) => failure = error,
        );
        await pumpEventQueue();

        // act
        fake.simulateDisconnection(address);
        await pumpEventQueue();

        // assert
        expect(
          failure,
          isA<DisconnectedException>().having(
            (e) => e.reason,
            'reason',
            DisconnectReason.linkLoss,
          ),
        );
      },
    );
  });

  group('A disconnect the platform fails', () {
    test(
      'a disconnect the platform fails leaves the Connection usable',
      () async {
        // arrange
        simulateSensor();
        final connection = await bluey.connect(device);
        final measurement = await measurementOf(connection);
        fake.enqueueFault(
          FakeOp.disconnect,
          const platform.GattOperationUnknownPlatformException(
            'disconnect',
            code: 'bluey-unknown',
            message: 'the radio refused',
          ),
        );

        // act
        final disconnecting = connection.disconnect();

        // assert
        await expectLater(disconnecting, throwsA(isA<BlueyException>()));
        expect(connection.state, ConnectionState.ready);
        expect(await measurement.read(), [0x01]);
      },
    );
  });

  group('A connect that overlaps the end of a requested disconnect', () {
    test('a connect made after the answer and before the ended link\'s last '
        'report gives a Connection that stays connected', () async {
      // arrange
      fake.simulatePeripheral(id: address);
      fake.disconnectSignals = FakeDisconnectSignals.answerThenReport;
      final connection = await bluey.connect(device);
      await connection.disconnect();

      // act
      final next = await bluey.connect(device);
      await pumpEventQueue();

      // assert
      expect(next, isNot(same(connection)));
      expect(next.state.isConnected, isTrue);
    });

    test('a connect made while the close is in flight gives a Connection that '
        'stays connected after the old answer arrives', () async {
      // arrange
      fake.simulatePeripheral(id: address);
      fake.disconnectSignals = FakeDisconnectSignals.reportThenAnswer;
      final connection = await bluey.connect(device);
      final closing = connection.disconnect();

      // act
      final next = bluey.connect(device);
      await closing;
      final reconnected = await next;
      await pumpEventQueue();

      // assert
      expect(reconnected, isNot(same(connection)));
      expect(reconnected.state.isConnected, isTrue);
    });
  });
}

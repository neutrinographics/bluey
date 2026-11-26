import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/value_objects/mtu.dart';
import 'package:bluey/src/features/connection/domain/value_objects/bond_state.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_interval.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_parameters.dart';
import 'package:bluey/src/features/connection/domain/value_objects/peripheral_latency.dart';
import 'package:bluey/src/features/connection/domain/value_objects/supervision_timeout.dart';
import 'package:bluey/src/features/connection/domain/value_objects/phy.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_bonding.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_connection_ports.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_link_features.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_links.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_mtu_negotiation.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_parameter_control.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_phy_control.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_signal_strength.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  test('its links are PlatformLinks over the platform it was given', () async {
    // arrange
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    final ports = platformConnectionPorts(fake, log: RecordingLog());

    // act
    await ports.links.open(device);

    // assert
    expect(ports.links, isA<PlatformLinks>());
    expect(fake.connectedDeviceIds, contains(device.value));
  });

  test('its features are what the platform says its links can do', () {
    // arrange
    const capabilities = Capabilities(
      platformKind: PlatformKind.android,
      canRequestMtu: true,
      maxMtu: 185,
      canBond: true,
    );
    final fake = FakeBlueyPlatform(capabilities: capabilities);

    // act
    final ports = platformConnectionPorts(fake, log: RecordingLog());

    // assert
    expect(ports.features, linkFeaturesFrom(capabilities));
  });

  test('its MTU negotiation and signal strength are over the platform it was '
      'given', () async {
    // arrange
    final fake =
        FakeBlueyPlatform()..simulatePeripheral(id: device.value, rssi: -42);
    final ports = platformConnectionPorts(fake, log: RecordingLog());
    final link = (await ports.links.open(
      device,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);

    // act
    final mtu = await ports.mtu.request(link, Mtu(185));
    final rssi = await ports.signal.read(link);

    // assert
    expect(ports.mtu, isA<PlatformMtuNegotiation>());
    expect(ports.signal, isA<PlatformSignalStrength>());
    expect(mtu, Right<ConnectionFailure, Mtu>(Mtu.fromPlatform(185)));
    expect(rssi, const Right<ConnectionFailure, int>(-42));
  });

  test('its bonding is over the platform it was given', () async {
    // arrange
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    final ports = platformConnectionPorts(fake, log: RecordingLog());
    final link = (await ports.links.open(
      device,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    fake.simulateBondState(device.value, PlatformBondState.bonded);

    // act
    final state = await ports.bonding.stateOf(link);

    // assert
    expect(ports.bonding, isA<PlatformBonding>());
    expect(state, const Right<ConnectionFailure, BondState>(BondState.bonded));
  });

  test('its PHY control is over the platform it was given', () async {
    // arrange
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    final ports = platformConnectionPorts(fake, log: RecordingLog());
    final link = (await ports.links.open(
      device,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    fake.simulatePhy(device.value, tx: PlatformPhy.le2m, rx: PlatformPhy.le2m);

    // act
    final pair = await ports.phy.pairOf(link);

    // assert
    expect(ports.phy, isA<PlatformPhyControl>());
    expect(
      pair,
      const Right<ConnectionFailure, PhyPair>((tx: Phy.le2m, rx: Phy.le2m)),
    );
  });

  test('its parameter control is over the platform it was given', () async {
    // arrange
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    final ports = platformConnectionPorts(fake, log: RecordingLog());
    final link = (await ports.links.open(
      device,
    )).fold((failure) => fail('the open failed: $failure'), (id) => id);
    fake.simulateConnectionParameters(
      device.value,
      const PlatformConnectionParameters(
        intervalMs: 15.0,
        latency: 4,
        timeoutMs: 2000,
      ),
    );

    // act
    final parameters = await ports.parameters.parametersOf(link);

    // assert
    expect(ports.parameters, isA<PlatformParameterControl>());
    expect(
      parameters,
      Right<ConnectionFailure, ConnectionParameters>(
        ConnectionParameters(
          interval: ConnectionInterval(15.0),
          latency: PeripheralLatency(4),
          timeout: SupervisionTimeout(2000),
        ),
      ),
    );
  });
}

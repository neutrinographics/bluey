import 'package:bluey/src/features/connection/application/ports/bonding.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/value_objects/bond_state.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_bonding.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/bonding_contract.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

const _device = 'AA:BB:CC:DD:EE:01';

void main() {
  bondingContract(
    'PlatformBonding over FakeBlueyPlatform',
    _FakePlatformHarness.connected,
  );

  test('a platform stream error is logged and the reports go on', () async {
    // arrange
    final h = await _FakePlatformHarness.connected();
    final seen = <BondState>[];
    final errors = <Object>[];
    h.bonding
        .changesOf(h.link)
        .listen(seen.add, onError: (Object error) => errors.add(error));

    // act
    h.fake.simulateBondStateError(_device, StateError('reports broke'));
    h.fake.simulateBondState(_device, PlatformBondState.bonded);
    await pumpEventQueue();

    // assert
    expect(seen, [BondState.bonded]);
    expect(errors, isEmpty);
    expect(
      h.log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [
        (
          BlueyLogLevel.warn,
          'bluey.connection',
          'bond state reports failed',
          'UnexpectedPlatformFailure',
        ),
      ],
    );
    expect(h.log.records.single.data, {'link': _device});
  });
}

class _FakePlatformHarness implements BondingHarness {
  _FakePlatformHarness._(this.fake, this.link);

  static Future<_FakePlatformHarness> connected() async {
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: _device);
    final id = await fake.connect(
      _device,
      const PlatformConnectConfig(timeoutMs: null, mtu: null),
    );
    return _FakePlatformHarness._(fake, LinkId(id));
  }

  final FakeBlueyPlatform fake;
  final RecordingLog log = RecordingLog();

  @override
  final LinkId link;

  @override
  late final Bonding bonding = PlatformBonding(fake, log: log);

  @override
  void answerReads(BondState state) =>
      fake.simulateBondState(_device, _platformStateOf(state));

  @override
  void radioReports(BondState state) =>
      fake.simulateBondState(_device, _platformStateOf(state));

  @override
  void timeOutNextRead() => fake.enqueueFault(
    FakeOp.getBondState,
    const GattOperationTimeoutException('getBondState'),
    deviceId: _device,
  );

  @override
  void rejectNextBond(int status) => fake.enqueueFault(
    FakeOp.bond,
    GattOperationStatusFailedException('bond', status),
    deviceId: _device,
  );
}

PlatformBondState _platformStateOf(BondState state) => switch (state) {
  BondState.none => PlatformBondState.none,
  BondState.bonding => PlatformBondState.bonding,
  BondState.bonded => PlatformBondState.bonded,
};

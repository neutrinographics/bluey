import 'package:bluey/src/features/connection/application/ports/phy_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/value_objects/phy.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_phy_control.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/phy_control_contract.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

const _device = 'AA:BB:CC:DD:EE:01';

void main() {
  phyControlContract(
    'PlatformPhyControl over FakeBlueyPlatform',
    () => _FakePlatformHarness.connected(FakeBlueyPlatform()),
  );

  group('each Phy maps to the PlatformPhy of the same name', () {
    for (final phy in Phy.values) {
      test('${phy.name} is asked for as ${phy.name} and read back as '
          'it', () async {
        // arrange
        final fake = _RequestRecordingPlatform();
        final h = await _FakePlatformHarness.connected(fake);
        h.fake.simulatePhy(
          _device,
          tx: _platformPhyNamed(phy.name),
          rx: _platformPhyNamed(phy.name),
        );

        // act
        await h.phy.request(h.link, tx: phy, rx: phy);
        final read = await h.phy.pairOf(h.link);

        // assert
        expect(fake.requests, [
          (tx: _platformPhyNamed(phy.name), rx: _platformPhyNamed(phy.name)),
        ]);
        expect(read, Right<ConnectionFailure, PhyPair>((tx: phy, rx: phy)));
      });
    }
  });

  test('a direction left out is asked for as none', () async {
    // arrange
    final fake = _RequestRecordingPlatform();
    final h = await _FakePlatformHarness.connected(fake);

    // act
    await h.phy.request(h.link, rx: Phy.leCoded);

    // assert
    expect(fake.requests, [(tx: null, rx: PlatformPhy.leCoded)]);
  });

  test('a platform stream error is logged and the reports go on', () async {
    // arrange
    final h = await _FakePlatformHarness.connected(FakeBlueyPlatform());
    final seen = <PhyPair>[];
    final errors = <Object>[];
    h.phy
        .changesOf(h.link)
        .listen(seen.add, onError: (Object error) => errors.add(error));

    // act
    h.fake.simulatePhyError(_device, StateError('reports broke'));
    h.fake.simulatePhy(_device, tx: PlatformPhy.le2m, rx: PlatformPhy.leCoded);
    await pumpEventQueue();

    // assert
    expect(seen, [(tx: Phy.le2m, rx: Phy.leCoded)]);
    expect(errors, isEmpty);
    expect(
      h.log.records.map((r) => (r.level, r.context, r.message, r.errorCode)),
      [
        (
          BlueyLogLevel.warn,
          'bluey.connection',
          'phy reports failed',
          'UnexpectedPlatformFailure',
        ),
      ],
    );
    expect(h.log.records.single.data, {'link': _device});
  });
}

PlatformPhy _platformPhyNamed(String name) =>
    PlatformPhy.values.singleWhere((phy) => phy.name == name);

/// The fake, keeping the directions each PHY request asked for.
final class _RequestRecordingPlatform extends FakeBlueyPlatform {
  final List<({PlatformPhy? tx, PlatformPhy? rx})> requests = [];

  @override
  Future<void> requestPhy(
    String deviceId,
    PlatformPhy? txPhy,
    PlatformPhy? rxPhy,
  ) {
    requests.add((tx: txPhy, rx: rxPhy));
    return super.requestPhy(deviceId, txPhy, rxPhy);
  }
}

class _FakePlatformHarness implements PhyControlHarness {
  _FakePlatformHarness._(this.fake, this.link);

  static Future<_FakePlatformHarness> connected(FakeBlueyPlatform fake) async {
    fake.simulatePeripheral(id: _device);
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
  late final PhyControl phy = PlatformPhyControl(fake, log: log);

  @override
  void answerReads(PhyPair pair) => _simulate(pair);

  @override
  void radioReports(PhyPair pair) => _simulate(pair);

  @override
  void timeOutNextRead() => fake.enqueueFault(
    FakeOp.getPhy,
    const GattOperationTimeoutException('getPhy'),
    deviceId: _device,
  );

  @override
  void rejectNextRequest(int status) => fake.enqueueFault(
    FakeOp.requestPhy,
    GattOperationStatusFailedException('requestPhy', status),
    deviceId: _device,
  );

  void _simulate(PhyPair pair) => fake.simulatePhy(
    _device,
    tx: _platformPhyNamed(pair.tx.name),
    rx: _platformPhyNamed(pair.rx.name),
  );
}

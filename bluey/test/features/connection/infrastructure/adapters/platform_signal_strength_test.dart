import 'package:bluey/src/features/connection/application/ports/signal_strength.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_signal_strength.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/signal_strength_contract.dart';

const _device = 'AA:BB:CC:DD:EE:01';

void main() {
  signalStrengthContract(
    'PlatformSignalStrength over FakeBlueyPlatform',
    _FakePlatformHarness.connected,
  );
}

class _FakePlatformHarness implements SignalStrengthHarness {
  _FakePlatformHarness._(this.fake, this.link);

  static Future<SignalStrengthHarness> connected() async {
    final fake =
        FakeBlueyPlatform()..simulatePeripheral(id: _device, rssi: -61);
    final id = await fake.connect(
      _device,
      const PlatformConnectConfig(timeoutMs: null, mtu: null),
    );
    return _FakePlatformHarness._(fake, LinkId(id));
  }

  final FakeBlueyPlatform fake;

  @override
  final LinkId link;

  @override
  int get rssi => -61;

  @override
  late final SignalStrength strength = PlatformSignalStrength(fake);

  @override
  void rejectNext(int status) => fake.enqueueFault(
    FakeOp.readRssi,
    GattOperationStatusFailedException('readRssi', status),
    deviceId: _device,
  );
}

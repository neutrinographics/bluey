import 'package:bluey/src/features/connection/application/ports/mtu_negotiation.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/value_objects/write_payload_limit.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_mtu_negotiation.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/mtu_negotiation_contract.dart';

const _device = 'AA:BB:CC:DD:EE:01';

void main() {
  mtuNegotiationContract(
    'PlatformMtuNegotiation over FakeBlueyPlatform',
    _FakePlatformHarness.connected,
  );

  test('a platform limit above 512 is answered as 512', () async {
    // arrange
    final h = await _FakePlatformHarness.connected();
    h.limitWrites(withResponse: 514, withoutResponse: 514);

    // act
    final answer = await h.negotiation.writePayloadLimit(
      h.link,
      withResponse: false,
    );

    // assert
    expect(
      answer,
      Right<ConnectionFailure, WritePayloadLimit>(WritePayloadLimit(512)),
    );
  });
}

class _FakePlatformHarness implements MtuNegotiationHarness {
  _FakePlatformHarness._(this.fake, this.link);

  static Future<MtuNegotiationHarness> connected() async {
    final fake = FakeBlueyPlatform()..simulatePeripheral(id: _device);
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
  late final MtuNegotiation negotiation = PlatformMtuNegotiation(fake);

  @override
  void settleAt(int mtu) => fake.simulateMtuNegotiationCap(_device, mtu);

  @override
  void rejectNext(int status) => fake.enqueueFault(
    FakeOp.requestMtu,
    GattOperationStatusFailedException('requestMtu', status),
    deviceId: _device,
  );

  @override
  void timeOutNext() => fake.enqueueFault(
    FakeOp.requestMtu,
    const GattOperationTimeoutException('requestMtu'),
    deviceId: _device,
  );

  @override
  void rejectNextLimitRead(int status) => fake.enqueueFault(
    FakeOp.getMaximumWriteLength,
    GattOperationStatusFailedException('getMaximumWriteLength', status),
    deviceId: _device,
  );

  @override
  void limitWrites({required int withResponse, required int withoutResponse}) =>
      fake.setMaxWriteLengthOverride(
        _device,
        withResponse: withResponse,
        withoutResponse: withoutResponse,
      );
}

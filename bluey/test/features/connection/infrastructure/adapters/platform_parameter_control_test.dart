import 'package:bluey/src/features/connection/application/ports/parameter_control.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_id.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_interval.dart';
import 'package:bluey/src/features/connection/domain/value_objects/connection_parameters.dart';
import 'package:bluey/src/features/connection/domain/value_objects/peripheral_latency.dart';
import 'package:bluey/src/features/connection/domain/value_objects/supervision_timeout.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_parameter_control.dart';
import 'package:bluey/src/shared/domain/either.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/parameter_control_contract.dart';

const _device = 'AA:BB:CC:DD:EE:01';

void main() {
  parameterControlContract(
    'PlatformParameterControl over FakeBlueyPlatform',
    () => _FakePlatformHarness.connected(FakeBlueyPlatform()),
  );

  test('maps interval, latency and timeout both ways', () async {
    // arrange
    final fake = _RequestRecordingPlatform();
    final h = await _FakePlatformHarness.connected(fake);
    fake.simulateConnectionParameters(
      _device,
      const PlatformConnectionParameters(
        intervalMs: 30.0,
        latency: 0,
        timeoutMs: 4000,
      ),
    );
    final defaults = ConnectionParameters(
      interval: ConnectionInterval(30.0),
      latency: PeripheralLatency(0),
      timeout: SupervisionTimeout(4000),
    );

    // act
    final read = await h.parameters.parametersOf(h.link);
    await h.parameters.request(h.link, defaults);

    // assert
    expect(read, Right<ConnectionFailure, ConnectionParameters>(defaults));
    expect(fake.requests.map((p) => (p.intervalMs, p.latency, p.timeoutMs)), [
      (30.0, 0, 4000),
    ]);
  });

  test('an answer outside the specification is a failure, not a '
      'throw', () async {
    // arrange
    final h = await _FakePlatformHarness.connected(FakeBlueyPlatform());
    h.fake.simulateConnectionParameters(
      _device,
      const PlatformConnectionParameters(
        intervalMs: 1.0,
        latency: 0,
        timeoutMs: 4000,
      ),
    );

    // act
    final read = await h.parameters.parametersOf(h.link);

    // assert
    expect(
      read.fold((failure) => failure, (_) => null),
      isA<UnexpectedPlatformFailure>().having(
        (f) => f.cause,
        'cause',
        isA<ArgumentError>(),
      ),
    );
  });
}

/// The fake, keeping the parameters each request asked for.
final class _RequestRecordingPlatform extends FakeBlueyPlatform {
  final List<PlatformConnectionParameters> requests = [];

  @override
  Future<void> requestConnectionParameters(
    String deviceId,
    PlatformConnectionParameters params,
  ) {
    requests.add(params);
    return super.requestConnectionParameters(deviceId, params);
  }
}

class _FakePlatformHarness implements ParameterControlHarness {
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

  @override
  final LinkId link;

  @override
  late final ParameterControl parameters = PlatformParameterControl(fake);

  @override
  void answerReads(ConnectionParameters parameters) =>
      fake.simulateConnectionParameters(
        _device,
        PlatformConnectionParameters(
          intervalMs: parameters.interval.milliseconds,
          latency: parameters.latency.events,
          timeoutMs: parameters.timeout.milliseconds,
        ),
      );

  @override
  void timeOutNextRead() => fake.enqueueFault(
    FakeOp.getConnectionParameters,
    const GattOperationTimeoutException('getConnectionParameters'),
    deviceId: _device,
  );

  @override
  void rejectNextRequest(int status) => fake.enqueueFault(
    FakeOp.requestConnectionParameters,
    GattOperationStatusFailedException('requestConnectionParameters', status),
    deviceId: _device,
  );
}

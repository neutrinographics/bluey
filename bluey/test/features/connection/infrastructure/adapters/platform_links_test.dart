import 'dart:async';

import 'package:bluey/src/features/connection/application/ports/links.dart';
import 'package:bluey/src/features/connection/domain/connection_failure.dart';
import 'package:bluey/src/features/connection/domain/link_end.dart';
import 'package:bluey/src/features/connection/domain/link_input.dart';
import 'package:bluey/src/features/connection/infrastructure/adapters/platform_links.dart';
import 'package:bluey/src/shared/application/log_level.dart';
import 'package:bluey/src/shared/domain/device_address.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import '../../../../fakes/fake_platform.dart';
import '../../../../fixtures/features/connection/application/ports/links_contract.dart';
import '../../../../fixtures/shared/application/recording_log.dart';

const device = DeviceAddress('AA:BB:CC:DD:EE:01');

void main() {
  linksContract(
    'PlatformLinks over FakeBlueyPlatform',
    () => _FakePlatformHarness(),
  );

  late FakeBlueyPlatform fake;
  late RecordingLog log;
  late PlatformLinks links;

  setUp(() {
    fake = FakeBlueyPlatform()..simulatePeripheral(id: device.value);
    log = RecordingLog();
    links = PlatformLinks(fake, log: log);
  });

  group('opening', () {
    test('open passes the caller\'s timeout to the platform', () async {
      // act
      await links.open(device, timeout: const Duration(seconds: 3));

      // assert
      expect(
        fake.lastConnectConfig,
        const PlatformConnectConfig(timeoutMs: 3000, mtu: null),
      );
    });

    test('open with no timeout leaves the bound to the platform', () async {
      // act
      await links.open(device);

      // assert
      expect(
        fake.lastConnectConfig,
        const PlatformConnectConfig(timeoutMs: null, mtu: null),
      );
    });
  });

  group('reports', () {
    test('a reports stream the platform fails ends as a drop', () async {
      // arrange
      final id = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final reports = links.reportsOf(id);

      // act
      fake.simulateConnectionStateError(device.value, StateError('boom'));

      // assert
      await expectLater(reports, emitsDone);
      await pumpEventQueue();
      expect(log.records.single.message, 'link reports failed');
      expect(log.records.single.level, BlueyLogLevel.warn);
      expect(log.records.single.context, 'bluey.connection');
      expect(fake.connectedDeviceIds, isEmpty);
    });

    test('a link the platform will not close after its reports failed is '
        'logged as left open, and its reports still end', () async {
      // arrange
      final id = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final reports = links.reportsOf(id);
      fake.enqueueFault(
        FakeOp.disconnect,
        PlatformException(code: 'E1'),
        deviceId: device.value,
      );

      // act
      fake.simulateConnectionStateError(device.value, StateError('boom'));

      // assert
      await expectLater(reports, emitsDone);
      await pumpEventQueue();
      expect(
        [
          for (final record in log.records)
            (record.level, record.context, record.message),
        ],
        [
          (BlueyLogLevel.warn, 'bluey.connection', 'link reports failed'),
          (BlueyLogLevel.warn, 'bluey.connection', 'link left open'),
        ],
      );
      expect(log.records.last.data, {'link': device.value});
    });
  });

  group('a link the platform keeps after its reader left', () {
    test('an open after the reports\' listener left carries the reports '
        'afresh', () async {
      // arrange
      final first = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      links.reportsOf(first).listen((_) {}).cancel().ignore();
      await pumpEventQueue();

      // act
      final again = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final reports = links.reportsOf(again);
      fake.simulateDisconnection(device.value);

      // assert
      await expectLater(
        reports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );
    });
  });

  group('closing', () {
    test('a close the platform fails on a live link answers why', () async {
      // arrange
      final id = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final error = PlatformException(code: 'E1', message: 'no channel');
      fake.enqueueFault(FakeOp.disconnect, error, deviceId: device.value);

      // act
      final answer = await links.close(id);

      // assert
      expect(
        answer.fold((failure) => failure, (_) => fail('close')),
        UnexpectedPlatformFailure('no channel', code: 'E1', cause: error),
      );
    });

    test('a close of a link that already dropped answers success without '
        'asking the platform', () async {
      // arrange
      final id = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      fake.simulateDisconnection(device.value);
      await pumpEventQueue();
      fake.enqueueFault(
        FakeOp.disconnect,
        PlatformException(code: 'E1'),
        deviceId: device.value,
      );

      // act
      final answer = await links.close(id);

      // assert
      expect(answer.fold((failure) => failure, (_) => null), isNull);
      await expectLater(
        fake.disconnect(device.value),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('carriers', () {
    test('holds no carrier once a link has ended', () async {
      // arrange
      final id = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final reports = links.reportsOf(id);

      // act
      fake.simulateDisconnection(device.value);
      await expectLater(
        reports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );

      // assert
      expect(links.carriedLinks, 0);
    });

    test('a late end of an old link leaves the new link\'s carrier in '
        'place', () async {
      // arrange
      final platform =
          _LateAnsweringPlatform()..simulatePeripheral(id: device.value);
      final links = PlatformLinks(platform, log: log);
      final first = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final firstReports = links.reportsOf(first);
      final closing = links.close(first);
      await expectLater(
        firstReports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );
      final again = (await links.open(
        device,
      )).fold((_) => fail('open'), (id) => id);
      final reports = links.reportsOf(again);

      // act
      platform.answerTheClose();
      await closing;

      // assert
      expect(links.carriedLinks, 1);
      platform.simulateDisconnection(device.value);
      await expectLater(
        reports,
        emitsInOrder([LinkReport.disconnected, emitsDone]),
      );
    });
  });

  group('outages', () {
    test('a failed adapter-state stream is an unknown outage', () async {
      // arrange
      final outages = <RadioOutage>[];
      final subscription = links.outages.listen(outages.add);

      // act
      fake.simulateStateError(StateError('boom'));
      await pumpEventQueue();

      // assert
      expect(outages, [RadioOutage.unknown]);
      subscription.cancel().ignore();
    });

    test('every adapter state but on is an outage', () async {
      // arrange
      final outages = <RadioOutage>[];
      final subscription = links.outages.listen(outages.add);

      // act
      for (final state in [
        BluetoothState.off,
        BluetoothState.unauthorized,
        BluetoothState.unsupported,
        BluetoothState.unknown,
        BluetoothState.on,
      ]) {
        fake.setBluetoothState(state);
      }
      await pumpEventQueue();

      // assert
      expect(outages, [
        RadioOutage.off,
        RadioOutage.unauthorized,
        RadioOutage.unsupported,
        RadioOutage.unknown,
      ]);
      subscription.cancel().ignore();
    });
  });
}

/// Ends a link at once but answers its disconnect only when told, so a close
/// can resolve after the device has been linked again.
final class _LateAnsweringPlatform extends FakeBlueyPlatform {
  final Completer<void> _answer = Completer<void>();

  void answerTheClose() => _answer.complete();

  @override
  Future<void> disconnect(String deviceId) async {
    await super.disconnect(deviceId);
    await _answer.future;
  }
}

/// Drives [FakeBlueyPlatform] into each situation [linksContract] describes,
/// so [PlatformLinks] is held to the promises the in-memory double keeps.
class _FakePlatformHarness implements LinksHarness {
  final FakeBlueyPlatform fake = FakeBlueyPlatform();

  @override
  late final Links links = PlatformLinks(fake, log: RecordingLog());

  @override
  void reach(DeviceAddress device) => fake.simulatePeripheral(id: device.value);

  @override
  void failNextOpen(DeviceAddress device, ConnectFailureReason reason) =>
      fake.simulateConnectFailure(device.value, switch (reason) {
        ConnectFailureReason.timeout => PlatformConnectFailureReason.timeout,
        ConnectFailureReason.deviceNotFound =>
          PlatformConnectFailureReason.deviceNotFound,
        ConnectFailureReason.deviceNotConnectable =>
          PlatformConnectFailureReason.notConnectable,
        ConnectFailureReason.pairingFailed =>
          PlatformConnectFailureReason.pairingFailed,
        ConnectFailureReason.connectionLimitReached =>
          PlatformConnectFailureReason.connectionLimitReached,
        ConnectFailureReason.unknown => PlatformConnectFailureReason.unknown,
      });

  @override
  void failNextClose(DeviceAddress device) => fake.enqueueFault(
    FakeOp.disconnect,
    PlatformException(code: 'disconnect-failed'),
    deviceId: device.value,
  );

  @override
  void drop(DeviceAddress device) => fake.simulateDisconnection(device.value);

  @override
  void orderCloseSignals(DeviceAddress device, CloseSignals order) =>
      fake.disconnectSignals = switch (order) {
        CloseSignals.reportThenAnswer => FakeDisconnectSignals.reportThenAnswer,
        CloseSignals.answerThenReport => FakeDisconnectSignals.answerThenReport,
      };

  @override
  void outage(RadioOutage outage) => fake.setBluetoothState(switch (outage) {
    RadioOutage.off => BluetoothState.off,
    RadioOutage.unauthorized => BluetoothState.unauthorized,
    RadioOutage.unsupported => BluetoothState.unsupported,
    RadioOutage.unknown => BluetoothState.unknown,
  });
}

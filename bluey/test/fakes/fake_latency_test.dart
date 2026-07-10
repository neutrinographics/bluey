import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';
import 'test_helpers.dart';

/// Contract tests for the fake's operation-latency knob (audit R3 / NT-2).
///
/// With `operationLatency` set, every platform operation takes virtual
/// time to complete (Timer-based, so `fakeAsync.elapse` drives it). This
/// is what creates real interleaving windows: two domain-level operations
/// can now genuinely overlap at await points, and a disconnect can race
/// an in-flight operation through the public API alone.
void main() {
  const deviceId = TestDeviceIds.device1;

  void simulateDevice(FakeBlueyPlatform fake, [String id = deviceId]) {
    fake.simulatePeripheral(
      id: id,
      name: 'Latency Test',
      services: [
        TestServiceBuilder(TestUuids.heartRateService)
            .withReadWrite(TestUuids.heartRateMeasurement)
            .withReadWrite(TestUuids.bodySensorLocation)
            .build(),
      ],
      characteristicValues: {
        TestUuids.heartRateMeasurement: Uint8List.fromList([0x01]),
        TestUuids.bodySensorLocation: Uint8List.fromList([0x02]),
      },
    );
  }

  /// Boots a Bluey instance against a fresh fake inside [fakeAsync].
  ({FakeBlueyPlatform fake, Bluey bluey}) boot(FakeAsync async) {
    final fake = FakeBlueyPlatform();
    platform.BlueyPlatform.instance = fake;
    late Bluey bluey;
    Bluey.create().then((b) => bluey = b);
    async.flushMicrotasks();
    simulateDevice(fake);
    return (fake: fake, bluey: bluey);
  }

  group('operationLatency', () {
    test('a read takes the configured virtual time to complete', () {
      fakeAsync((async) {
        final env = boot(async);
        late Connection connection;
        env.bluey
            .connect(Device(address: const DeviceAddress(deviceId)))
            .then((c) => connection = c);
        async.flushMicrotasks();
        late RemoteCharacteristic characteristic;
        connection.services().then(
          (services) => characteristic = services.first.characteristics().first,
        );
        async.flushMicrotasks();

        env.fake.operationLatency = const Duration(milliseconds: 100);

        Uint8List? result;
        characteristic.read().then((v) => result = v);
        async.flushMicrotasks();
        expect(result, isNull, reason: 'read must still be in flight');

        async.elapse(const Duration(milliseconds: 99));
        expect(result, isNull, reason: 'latency has not fully elapsed');

        async.elapse(const Duration(milliseconds: 2));
        expect(result, equals([0x01]));

        env.bluey.dispose();
        env.fake.dispose();
        async.flushMicrotasks();
      });
    });

    test('connect honors the latency too', () {
      fakeAsync((async) {
        final env = boot(async);
        env.fake.operationLatency = const Duration(milliseconds: 50);

        Connection? connection;
        env.bluey
            .connect(Device(address: const DeviceAddress(deviceId)))
            .then((c) => connection = c);
        async.flushMicrotasks();
        expect(connection, isNull);

        async.elapse(const Duration(milliseconds: 51));
        expect(connection, isNotNull);
        expect(connection!.state, ConnectionState.linked);

        env.bluey.dispose();
        env.fake.dispose();
        async.flushMicrotasks();
      });
    });

    test('two operations started together genuinely overlap in flight',
        () {
      fakeAsync((async) {
        final env = boot(async);
        late Connection connection;
        env.bluey
            .connect(Device(address: const DeviceAddress(deviceId)))
            .then((c) => connection = c);
        async.flushMicrotasks();
        late List<RemoteCharacteristic> chars;
        connection.services().then(
          (services) => chars = services.first.characteristics(),
        );
        async.flushMicrotasks();

        env.fake.operationLatency = const Duration(milliseconds: 100);

        Uint8List? readResult;
        var writeDone = false;
        chars[0].read().then((v) => readResult = v);
        chars[1].write(Uint8List.fromList([0xEE])).then((_) => writeDone = true);
        async.flushMicrotasks();

        // Both are in flight simultaneously — the interleaving window
        // the synchronous fake never had.
        expect(env.fake.readCharacteristicCalls, hasLength(1));
        expect(env.fake.writeCharacteristicCalls, hasLength(1));
        expect(readResult, isNull);
        expect(writeDone, isFalse);

        async.elapse(const Duration(milliseconds: 101));
        expect(readResult, equals([0x01]));
        expect(writeDone, isTrue);

        env.bluey.dispose();
        env.fake.dispose();
        async.flushMicrotasks();
      });
    });

    test('a disconnect can race an in-flight write through the public API',
        () {
      fakeAsync((async) {
        final env = boot(async);
        late Connection connection;
        env.bluey
            .connect(Device(address: const DeviceAddress(deviceId)))
            .then((c) => connection = c);
        async.flushMicrotasks();
        late RemoteCharacteristic characteristic;
        connection.services().then(
          (services) => characteristic = services.first.characteristics().first,
        );
        async.flushMicrotasks();

        env.fake.operationLatency = const Duration(milliseconds: 100);

        Object? error;
        characteristic
            .write(Uint8List.fromList([0xDD]))
            .catchError((Object e) => error = e);
        async.flushMicrotasks();

        // The link drops while the write is still in transit.
        async.elapse(const Duration(milliseconds: 50));
        env.fake.simulateDisconnection(deviceId);
        async.elapse(const Duration(milliseconds: 51));

        expect(
          error,
          isA<BlueyException>(),
          reason: 'the raced write must surface a typed domain error',
        );

        env.bluey.dispose();
        env.fake.dispose();
        async.flushMicrotasks();
      });
    });
  });
}

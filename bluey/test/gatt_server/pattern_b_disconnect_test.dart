import 'dart:typed_data';
import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    show BlueyPlatform;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_platform.dart';

const _mac = 'AA:BB:CC:DD:EE:FF';
const _char = '0000fff1-0000-1000-8000-00805f9b34fb';
const _interval = Duration(seconds: 5);

void main() {
  test(
      'iOS: presence-unsubscribe (centralDisconnections) emits disconnections + removes session',
      () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final gone = <ClientAddress>[];
      server.disconnections.listen(gone.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateCentralDisconnection(_mac); // = iOS didUnsubscribe(presence)
      async.flushMicrotasks();
      expect(gone, equals([const ClientAddress(_mac)]),
          reason: 'centralDisconnection must emit exactly one disconnections event');
      expect(server.isClientConnected(const ClientAddress(_mac)), isFalse);
      server.dispose();
      bluey.dispose();
    });
  });

  test(
      'Pattern-B: reconnect after presence-disconnect re-establishes cleanly (no eviction loop)',
      () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final forwarded = <WriteRequest>[];
      server.writeRequests.listen(forwarded.add);

      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateCentralDisconnection(_mac);
      async.flushMicrotasks();
      // Reconnect (same identity — centralDisconnection cleared the session;
      // a fresh centralConnection re-announces and re-establishes it).
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();

      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue,
          reason: 'reconnect re-establishes the session — no eviction loop');
      fake.simulateWriteRequest(
        centralId: _mac,
        characteristicUuid: _char,
        value: Uint8List.fromList([1]),
        responseNeeded: false,
      );
      async.flushMicrotasks();
      expect(forwarded, hasLength(1));
      server.dispose();
      bluey.dispose();
    });
  });

  test(
      'no eviction under the flip: silence then a request is serviced, not evicted',
      () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final forwarded = <WriteRequest>[];
      server.writeRequests.listen(forwarded.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.fireLifecycleSilence(_mac);
      async.flushMicrotasks();
      async.elapse(_interval); // silence fires — advisory on authoritative, session retained
      async.flushMicrotasks();
      fake.simulateWriteRequest(
        centralId: _mac,
        characteristicUuid: _char,
        value: Uint8List.fromList([2]),
        responseNeeded: false,
      );
      async.flushMicrotasks();
      expect(forwarded, hasLength(1),
          reason:
              'session retained through silence → request serviced, not evicted');
      server.dispose();
      bluey.dispose();
    });
  });

  test(
      'didUnsubscribe-miss: a silent link loss is NOT detected (justifies the dormant eviction fallback)',
      () async {
    final fake = FakeBlueyPlatform(reportsCentralDisconnects: true);
    BlueyPlatform.instance = fake;
    final bluey = await Bluey.create();
    fakeAsync((async) {
      final server = bluey.server(lifecycleInterval: _interval)!;
      server.startAdvertising(name: 't');
      async.flushMicrotasks();
      final gone = <ClientAddress>[];
      server.disconnections.listen(gone.add);
      fake.simulateCentralConnection(centralId: _mac);
      async.flushMicrotasks();
      fake.simulateSilentLinkLoss(_mac); // didUnsubscribe didn't fire
      async.flushMicrotasks();
      async.elapse(_interval * 3); // even long silence is advisory under the flip
      expect(gone, isEmpty,
          reason: 'without the didUnsubscribe signal, the loss is missed — '
              'the explicit, visible cost of Pattern B; covered by re-enabling '
              'the dormant eviction (reportsCentralDisconnects=false) if hardware proves the signal flaky');
      expect(server.isClientConnected(const ClientAddress(_mac)), isTrue);
      server.dispose();
      bluey.dispose();
    });
  });
}

import 'dart:typed_data';

import 'package:bluey/bluey.dart';
import 'package:bluey_example/features/server/infrastructure/stress_service_handler.dart';
import 'package:bluey_example/shared/stress_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../mocks/mock_bluey.dart';

void main() {
  late MockServer mockServer;
  late MockClient mockClient;

  setUpAll(() {
    registerFallbackValue(FakeUUID());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      WriteRequest(
        client: MockClient(),
        characteristicId: UUID('00000000-0000-0000-0000-000000000000'),
        value: Uint8List(0),
        offset: 0,
        responseNeeded: false,
        internalRequestId: 0,
      ),
    );
    registerFallbackValue(GattResponseStatus.success);
  });

  setUp(() {
    mockServer = MockServer();
    mockClient = MockClient();
    when(() => mockClient.id)
        .thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
    when(() => mockServer.respondToWrite(
          any(),
          status: any(named: 'status'),
        )).thenAnswer((_) async {});
    when(() => mockServer.notify(any(), data: any(named: 'data')))
        .thenAnswer((_) async {});
  });

  group('StressServiceHandler — Echo', () {
    test('echo stores payload, responds success, and notifies', () async {
      final handler = StressServiceHandler();
      final payload = Uint8List.fromList([0xAA, 0xBB, 0xCC]);

      final write = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: EchoCommand(payload).encode(),
        offset: 0,
        responseNeeded: true,
        internalRequestId: 1,
      );

      await handler.onWrite(write, mockServer);

      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);
      verify(() => mockServer.notify(
            UUID(StressProtocol.charUuid),
            data: payload,
          )).called(1);

      // Read after echo returns the stored payload.
      final readResponse = handler.onRead();
      expect(readResponse, equals(payload));
    });
  });

  group('StressServiceHandler — BurstMe', () {
    test('burstMe responds success then fires N notifications with burst-id prefix', () async {
      final handler = StressServiceHandler();
      final write = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: const BurstMeCommand(count: 3, payloadSize: 4).encode(),
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );

      await handler.onWrite(write, mockServer);

      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);

      // 3 notifications, each: [burstId, 0x00, 0x01, 0x02, 0x03]
      final captured = verify(() => mockServer.notify(
            any(),
            data: captureAny(named: 'data'),
          )).captured.cast<Uint8List>();
      expect(captured, hasLength(3));
      final firstBurstId = captured.first.first;
      for (final notif in captured) {
        expect(notif.first, equals(firstBurstId),
            reason: 'all notifs in one burst share id');
        expect(notif.sublist(1), equals(Uint8List.fromList([0x00, 0x01, 0x02, 0x03])));
      }
    });

    test('successive burstMe commands use incrementing burst-ids', () async {
      final handler = StressServiceHandler();
      Uint8List makeBurst(int count) =>
          BurstMeCommand(count: count, payloadSize: 1).encode();

      WriteRequest burstWrite(Uint8List value) => WriteRequest(
            client: mockClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: value,
            responseNeeded: true,
            offset: 0,
            internalRequestId: 0,
          );

      await handler.onWrite(burstWrite(makeBurst(1)), mockServer);
      await handler.onWrite(burstWrite(makeBurst(1)), mockServer);

      final captured = verify(() => mockServer.notify(
            any(),
            data: captureAny(named: 'data'),
          )).captured.cast<Uint8List>();
      expect(captured, hasLength(2));
      expect(captured[1].first, equals((captured[0].first + 1) & 0xff));
    });
  });

  group('StressServiceHandler — DelayAck', () {
    test('delayAck waits the requested duration before responding', () async {
      final handler = StressServiceHandler();
      final write = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: const DelayAckCommand(delayMs: 50).encode(),
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );

      final stopwatch = Stopwatch()..start();
      await handler.onWrite(write, mockServer);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(50));
      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);
    });
  });

  group('StressServiceHandler — DropNext', () {
    test('dropNext sets flag; next write is silent and self-clears', () async {
      final handler = StressServiceHandler();

      WriteRequest writeOf(Uint8List value) => WriteRequest(
            client: mockClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: value,
            responseNeeded: true,
            offset: 0,
            internalRequestId: 0,
          );

      // First write: DropNext itself acks normally.
      final dropCmd = writeOf(const DropNextCommand().encode());
      await handler.onWrite(dropCmd, mockServer);
      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);
      clearInteractions(mockServer);
      when(() => mockServer.respondToWrite(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockServer.notify(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});

      // Second write: dropped silently.
      final droppedWrite = writeOf(
        EchoCommand(Uint8List.fromList([0x42])).encode(),
      );
      await handler.onWrite(droppedWrite, mockServer);
      verifyNever(() => mockServer.respondToWrite(
            any(),
            status: any(named: 'status'),
          ));
      verifyNever(() => mockServer.notify(any(), data: any(named: 'data')));

      // Third write: flag self-cleared, echo normally.
      final normalWrite = writeOf(
        EchoCommand(Uint8List.fromList([0x99])).encode(),
      );
      await handler.onWrite(normalWrite, mockServer);
      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);
    });
  });

  group('StressServiceHandler — SetPayloadSize', () {
    test('setPayloadSize changes the size of subsequent reads', () async {
      final handler = StressServiceHandler();
      expect(handler.onRead(), hasLength(20)); // default

      final cmd = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: const SetPayloadSizeCommand(sizeBytes: 50).encode(),
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );
      await handler.onWrite(cmd, mockServer);

      expect(handler.onRead(), hasLength(50));
    });
  });

  group('StressServiceHandler — unknown opcode', () {
    test('unknown opcode responds with requestNotSupported', () async {
      final handler = StressServiceHandler();
      final write = WriteRequest(
        client: mockClient,
        characteristicId: UUID(StressProtocol.charUuid),
        value: Uint8List.fromList([0xFF]), // unknown opcode
        responseNeeded: true,
        offset: 0,
        internalRequestId: 0,
      );

      await handler.onWrite(write, mockServer);

      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.requestNotSupported,
          )).called(1);
    });
  });

  group('StressServiceHandler — Reset', () {
    test('reset clears all state', () async {
      final handler = StressServiceHandler();

      WriteRequest writeOf(Uint8List value) => WriteRequest(
            client: mockClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: value,
            responseNeeded: true,
            offset: 0,
            internalRequestId: 0,
          );

      // Set state on the handler.
      await handler.onWrite(
        writeOf(EchoCommand(Uint8List.fromList([0xAA, 0xBB])).encode()),
        mockServer,
      );
      await handler.onWrite(
        writeOf(const SetPayloadSizeCommand(sizeBytes: 100).encode()),
        mockServer,
      );
      await handler.onWrite(
        writeOf(const DropNextCommand().encode()),
        mockServer,
      );

      // Now reset.
      await handler.onWrite(
        writeOf(const ResetCommand().encode()),
        mockServer,
      );

      // _lastEcho cleared → reads return pattern of default size 20.
      expect(handler.onRead(), hasLength(20));

      // _dropNextWrite cleared → next write echoes normally (not dropped).
      clearInteractions(mockServer);
      when(() => mockServer.respondToWrite(any(), status: any(named: 'status')))
          .thenAnswer((_) async {});
      when(() => mockServer.notify(any(), data: any(named: 'data')))
          .thenAnswer((_) async {});
      final probe = writeOf(EchoCommand(Uint8List.fromList([0x99])).encode());
      await handler.onWrite(probe, mockServer);
      verify(() => mockServer.respondToWrite(
            any(),
            status: GattResponseStatus.success,
          )).called(1);
    });

    test('reset interrupts an in-flight burstMe loop', () async {
      final handler = StressServiceHandler();

      WriteRequest writeOf(Uint8List value) => WriteRequest(
            client: mockClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: value,
            responseNeeded: true,
            offset: 0,
            internalRequestId: 0,
          );

      // Configure mockServer.notify so that the second notification
      // triggers a reset mid-loop.
      var notifyCount = 0;
      when(() => mockServer.notify(any(), data: any(named: 'data')))
          .thenAnswer((_) async {
        notifyCount++;
        if (notifyCount == 2) {
          // Mid-burst: fire a reset that flips _abortBurst.
          await handler.onWrite(
            writeOf(const ResetCommand().encode()),
            mockServer,
          );
        }
      });

      await handler.onWrite(
        writeOf(const BurstMeCommand(count: 100, payloadSize: 4).encode()),
        mockServer,
      );

      // Should have aborted well before 100 — exact count depends on
      // event-loop microtask ordering, but << 100.
      expect(notifyCount, lessThan(10),
          reason: 'reset should have aborted the burst quickly');
    });
  });
}

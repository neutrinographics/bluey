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
}

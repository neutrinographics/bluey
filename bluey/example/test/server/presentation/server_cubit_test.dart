import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/presentation/server_cubit.dart';
import 'package:bluey_example/features/server/presentation/server_state.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockCheckServerSupport mockCheckServerSupport;
  late MockStartAdvertising mockStartAdvertising;
  late MockStopAdvertising mockStopAdvertising;
  late MockAddService mockAddService;
  late MockSendNotification mockSendNotification;
  late MockObserveConnections mockObserveConnections;
  late MockDisconnectClient mockDisconnectClient;
  late MockDisposeServer mockDisposeServer;
  late MockGetConnectedClients mockGetConnectedClients;
  late MockObserveDisconnections mockObserveDisconnections;
  late MockObserveReadRequests mockObserveReadRequests;
  late MockObserveWriteRequests mockObserveWriteRequests;

  setUpAll(() {
    registerFallbackValue(FakeHostedService());
    registerFallbackValue(FakeUUID());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(MockClient());
    registerFallbackValue(<UUID>[]);
  });

  setUp(() {
    mockCheckServerSupport = MockCheckServerSupport();
    mockStartAdvertising = MockStartAdvertising();
    mockStopAdvertising = MockStopAdvertising();
    mockAddService = MockAddService();
    mockSendNotification = MockSendNotification();
    mockObserveConnections = MockObserveConnections();
    mockDisconnectClient = MockDisconnectClient();
    mockDisposeServer = MockDisposeServer();
    mockGetConnectedClients = MockGetConnectedClients();
    mockObserveDisconnections = MockObserveDisconnections();
    mockObserveReadRequests = MockObserveReadRequests();
    mockObserveWriteRequests = MockObserveWriteRequests();

    when(() => mockDisposeServer()).thenAnswer((_) async {});
    when(() => mockGetConnectedClients()).thenReturn([]);
    when(
      () => mockObserveDisconnections(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockObserveReadRequests(),
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockObserveWriteRequests(),
    ).thenAnswer((_) => const Stream.empty());
  });

  ServerCubit createCubit() {
    return ServerCubit(
      checkServerSupport: mockCheckServerSupport,
      startAdvertising: mockStartAdvertising,
      stopAdvertising: mockStopAdvertising,
      addService: mockAddService,
      sendNotification: mockSendNotification,
      observeConnections: mockObserveConnections,
      disconnectClient: mockDisconnectClient,
      disposeServer: mockDisposeServer,
      getConnectedClients: mockGetConnectedClients,
      observeDisconnections: mockObserveDisconnections,
      observeReadRequests: mockObserveReadRequests,
      observeWriteRequests: mockObserveWriteRequests,
    );
  }

  group('ServerCubit', () {
    test('initial state is correct', () {
      when(() => mockCheckServerSupport()).thenReturn(true);
      final cubit = createCubit();
      expect(cubit.state.isSupported, isTrue);
      expect(cubit.state.isAdvertising, isFalse);
      expect(cubit.state.connectedClients, isEmpty);
      expect(cubit.state.log, isEmpty);
      expect(cubit.state.error, isNull);
      cubit.close();
    });

    blocTest<ServerCubit, ServerScreenState>(
      'initialize sets isSupported false when server not supported',
      setUp: () {
        when(() => mockCheckServerSupport()).thenReturn(false);
      },
      build: createCubit,
      act: (cubit) => cubit.initialize(),
      verify: (cubit) {
        expect(cubit.state.isSupported, isFalse);
        expect(cubit.state.log, isNotEmpty);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'initialize succeeds when server is supported',
      setUp: () {
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockAddService(any())).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) => cubit.initialize(),
      verify: (cubit) {
        expect(cubit.state.isSupported, isTrue);
        verify(() => mockAddService(any())).called(1);
        expect(
          cubit.state.log.any((e) => e.message.contains('Initialized')),
          isTrue,
        );
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'initialize emits error when addService fails',
      setUp: () {
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockAddService(any())).thenThrow(Exception('Failed to add'));
      },
      build: createCubit,
      act: (cubit) => cubit.initialize(),
      verify: (cubit) {
        expect(cubit.state.error, contains('Failed to initialize server'));
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'startAdvertising sets isAdvertising true',
      setUp: () {
        when(
          () => mockStartAdvertising(
            name: any(named: 'name'),
            services: any(named: 'services'),
          ),
        ).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) => cubit.startAdvertising(),
      verify: (cubit) {
        expect(cubit.state.isAdvertising, isTrue);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'startAdvertising emits error on failure',
      setUp: () {
        when(
          () => mockStartAdvertising(
            name: any(named: 'name'),
            services: any(named: 'services'),
          ),
        ).thenThrow(Exception('Advertising failed'));
      },
      build: createCubit,
      act: (cubit) => cubit.startAdvertising(),
      verify: (cubit) {
        expect(cubit.state.error, contains('Failed to start advertising'));
        expect(cubit.state.isAdvertising, isFalse);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'stopAdvertising sets isAdvertising false',
      setUp: () {
        when(() => mockStopAdvertising()).thenAnswer((_) async {});
      },
      build: createCubit,
      seed: () => const ServerScreenState(isAdvertising: true),
      act: (cubit) => cubit.stopAdvertising(),
      verify: (cubit) {
        expect(cubit.state.isAdvertising, isFalse);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'stopAdvertising emits error on failure',
      setUp: () {
        when(() => mockStopAdvertising()).thenThrow(Exception('Stop failed'));
      },
      build: createCubit,
      seed: () => const ServerScreenState(isAdvertising: true),
      act: (cubit) => cubit.stopAdvertising(),
      verify: (cubit) {
        expect(cubit.state.error, contains('Failed to stop advertising'));
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'sendNotification emits error when no centrals connected',
      build: createCubit,
      act: (cubit) => cubit.sendNotification(),
      verify: (cubit) {
        expect(cubit.state.error, 'No clients connected');
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'sendNotification succeeds and increments count',
      setUp: () {
        when(() => mockSendNotification(any(), any())).thenAnswer((_) async {});
      },
      build: createCubit,
      seed: () {
        final client = MockClient();
        when(
          () => client.id,
        ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
        return ServerScreenState(connectedClients: [client]);
      },
      act: (cubit) => cubit.sendNotification(),
      verify: (cubit) {
        expect(cubit.state.notificationCount, 1);
        verify(() => mockSendNotification(any(), any())).called(1);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'sendNotification emits error on failure',
      setUp: () {
        when(
          () => mockSendNotification(any(), any()),
        ).thenThrow(Exception('Send failed'));
      },
      build: createCubit,
      seed: () {
        final client = MockClient();
        when(
          () => client.id,
        ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
        return ServerScreenState(connectedClients: [client]);
      },
      act: (cubit) => cubit.sendNotification(),
      verify: (cubit) {
        expect(cubit.state.error, contains('Failed to send notification'));
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'disconnectClient refreshes centrals list',
      setUp: () {
        when(() => mockDisconnectClient(any())).thenAnswer((_) async {});
        when(() => mockGetConnectedClients()).thenReturn([]);
      },
      build: createCubit,
      seed: () {
        final client = MockClient();
        when(
          () => client.id,
        ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
        return ServerScreenState(connectedClients: [client]);
      },
      act: (cubit) {
        final client = cubit.state.connectedClients.first;
        return cubit.disconnectClient(client);
      },
      verify: (cubit) {
        expect(cubit.state.connectedClients, isEmpty);
        verify(() => mockDisconnectClient(any())).called(1);
        verify(() => mockGetConnectedClients()).called(greaterThanOrEqualTo(1));
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'disconnectClient emits error on failure',
      setUp: () {
        when(
          () => mockDisconnectClient(any()),
        ).thenThrow(Exception('Disconnect failed'));
      },
      build: createCubit,
      seed: () {
        final client = MockClient();
        when(
          () => client.id,
        ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
        return ServerScreenState(connectedClients: [client]);
      },
      act: (cubit) {
        final client = cubit.state.connectedClients.first;
        return cubit.disconnectClient(client);
      },
      verify: (cubit) {
        expect(cubit.state.error, contains('Failed to disconnect'));
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'clearError clears the error',
      build: createCubit,
      seed: () => const ServerScreenState(error: 'Some error'),
      act: (cubit) => cubit.clearError(),
      expect:
          () => [
            isA<ServerScreenState>().having((s) => s.error, 'error', isNull),
          ],
    );

    blocTest<ServerCubit, ServerScreenState>(
      'clearLog clears the log',
      build: createCubit,
      seed: () => ServerScreenState(log: [ServerLogEntry('Test', 'message')]),
      act: (cubit) => cubit.clearLog(),
      expect:
          () => [isA<ServerScreenState>().having((s) => s.log, 'log', isEmpty)],
    );

    blocTest<ServerCubit, ServerScreenState>(
      'initialize refreshes centrals from library when stream emits',
      setUp: () {
        final client = MockClient();
        when(
          () => client.id,
        ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => Stream.value(client));
        when(() => mockAddService(any())).thenAnswer((_) async {});
        when(() => mockGetConnectedClients()).thenReturn([client]);
      },
      build: createCubit,
      act: (cubit) async {
        await cubit.initialize();
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.connectedClients, hasLength(1));
        verify(() => mockGetConnectedClients()).called(greaterThanOrEqualTo(1));
      },
    );

    test('close calls disposeServer', () async {
      when(() => mockCheckServerSupport()).thenReturn(true);
      final cubit = createCubit();
      await cubit.close();
      verify(() => mockDisposeServer()).called(1);
    });
  });
}

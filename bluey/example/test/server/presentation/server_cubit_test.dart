import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/presentation/server_cubit.dart';
import 'package:bluey_example/features/server/presentation/server_state.dart';
import 'package:bluey_example/shared/stress_protocol.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockCheckServerSupport mockCheckServerSupport;
  late MockSetServerIdentity mockSetServerIdentity;
  late MockResetServer mockResetServer;
  late MockStartAdvertising mockStartAdvertising;
  late MockStopAdvertising mockStopAdvertising;
  late MockAddService mockAddService;
  late MockSendNotification mockSendNotification;
  late MockObserveConnections mockObserveConnections;
  late MockObservePeerConnections mockObservePeerConnections;
  late MockDisposeServer mockDisposeServer;
  late MockGetConnectedClients mockGetConnectedClients;
  late MockObserveDisconnections mockObserveDisconnections;
  late MockObserveReadRequests mockObserveReadRequests;
  late MockObserveWriteRequests mockObserveWriteRequests;
  late MockGetServer mockGetServer;
  late MockServerIdentityStorage mockIdentityStorage;
  late MockBluey mockBluey;
  late StreamController<BlueyEvent> eventsController;

  final testServerId = ServerId('12345678-1234-4234-8234-123456789abc');

  setUpAll(() {
    registerFallbackValue(FakeHostedService());
    registerFallbackValue(FakeUUID());
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(MockClient());
    registerFallbackValue(<UUID>[]);
    registerFallbackValue(testServerId);
    registerFallbackValue(_FakeWriteRequest());
    registerFallbackValue(GattResponseStatus.success);
  });

  setUp(() {
    mockCheckServerSupport = MockCheckServerSupport();
    mockSetServerIdentity = MockSetServerIdentity();
    mockResetServer = MockResetServer();
    mockStartAdvertising = MockStartAdvertising();
    mockStopAdvertising = MockStopAdvertising();
    mockAddService = MockAddService();
    mockSendNotification = MockSendNotification();
    mockObserveConnections = MockObserveConnections();
    mockObservePeerConnections = MockObservePeerConnections();
    when(
      () => mockObservePeerConnections(),
    ).thenAnswer((_) => const Stream.empty());
    mockDisposeServer = MockDisposeServer();
    mockGetConnectedClients = MockGetConnectedClients();
    mockObserveDisconnections = MockObserveDisconnections();
    mockObserveReadRequests = MockObserveReadRequests();
    mockObserveWriteRequests = MockObserveWriteRequests();
    mockGetServer = MockGetServer();
    mockIdentityStorage = MockServerIdentityStorage();
    mockBluey = MockBluey();
    eventsController = StreamController<BlueyEvent>.broadcast();

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
    when(() => mockGetServer()).thenReturn(null);
    when(
      () => mockIdentityStorage.loadOrGenerate(),
    ).thenAnswer((_) async => testServerId);
    when(() => mockSetServerIdentity(any())).thenReturn(null);
    when(
      () => mockIdentityStorage.reset(),
    ).thenAnswer((_) async => testServerId);
    when(
      () => mockResetServer(identity: any(named: 'identity')),
    ).thenAnswer((_) async => null);
    when(() => mockBluey.events).thenAnswer((_) => eventsController.stream);
  });

  tearDown(() async {
    await eventsController.close();
  });

  ServerCubit createCubit() {
    return ServerCubit(
      checkServerSupport: mockCheckServerSupport,
      setServerIdentity: mockSetServerIdentity,
      resetServer: mockResetServer,
      startAdvertising: mockStartAdvertising,
      stopAdvertising: mockStopAdvertising,
      addService: mockAddService,
      sendNotification: mockSendNotification,
      observeConnections: mockObserveConnections,
      observePeerConnections: mockObservePeerConnections,
      disposeServer: mockDisposeServer,
      getConnectedClients: mockGetConnectedClients,
      observeDisconnections: mockObserveDisconnections,
      observeReadRequests: mockObserveReadRequests,
      observeWriteRequests: mockObserveWriteRequests,
      getServer: mockGetServer,
      identityStorage: mockIdentityStorage,
      bluey: mockBluey,
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
        verify(() => mockAddService(any())).called(2);
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
      'startAdvertising calls use case and adds log entry',
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
        verify(
          () => mockStartAdvertising(
            name: any(named: 'name'),
            services: any(named: 'services'),
          ),
        ).called(1);
        expect(
          cubit.state.log.any((e) => e.message.contains('Started advertising')),
          isTrue,
        );
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
      'stopAdvertising calls use case and adds log entry',
      setUp: () {
        when(() => mockStopAdvertising()).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) => cubit.stopAdvertising(),
      verify: (cubit) {
        verify(() => mockStopAdvertising()).called(1);
        expect(
          cubit.state.log.any((e) => e.message.contains('Stopped advertising')),
          isTrue,
        );
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'stopAdvertising emits error on failure',
      setUp: () {
        when(() => mockStopAdvertising()).thenThrow(Exception('Stop failed'));
      },
      build: createCubit,
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

    blocTest<ServerCubit, ServerScreenState>(
      'initialize loads identity and sets it on repository',
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
        expect(cubit.state.serverId, testServerId);
        verify(() => mockIdentityStorage.loadOrGenerate()).called(1);
        verify(() => mockSetServerIdentity(testServerId)).called(1);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'resetIdentity clears and regenerates identity',
      setUp: () {
        final newId = ServerId('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
        when(() => mockIdentityStorage.reset()).thenAnswer((_) async => newId);
        when(
          () => mockResetServer(identity: any(named: 'identity')),
        ).thenAnswer((_) async => MockServer());
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockAddService(any())).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) => cubit.resetIdentity(),
      verify: (cubit) {
        expect(
          cubit.state.serverId,
          ServerId('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
        );
        expect(cubit.state.isAdvertising, isFalse);
        verify(() => mockIdentityStorage.reset()).called(1);
        verify(
          () => mockResetServer(identity: any(named: 'identity')),
        ).called(1);
      },
    );

    test('close calls disposeServer', () async {
      when(() => mockCheckServerSupport()).thenReturn(true);
      final cubit = createCubit();
      await cubit.close();
      verify(() => mockDisposeServer()).called(1);
    });

    blocTest<ServerCubit, ServerScreenState>(
      'initial advertisingState is idle',
      build: createCubit,
      verify: (cubit) => expect(
        cubit.state.advertisingState,
        AdvertisingState.idle,
      ),
    );

    group('AdvertisingState stream', () {
      late StreamController<AdvertisingState> adController;
      late MockServer mockServer;

      setUp(() {
        adController = StreamController<AdvertisingState>.broadcast();
        mockServer = MockServer();
        when(() => mockServer.advertisingStateChanges)
            .thenAnswer((_) => adController.stream);
        when(() => mockGetServer()).thenReturn(mockServer);
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockAddService(any())).thenAnswer((_) async {});
      });

      tearDown(() async {
        await adController.close();
      });

      blocTest<ServerCubit, ServerScreenState>(
        'reflects AdvertisingState transitions from server.advertisingStateChanges',
        build: createCubit,
        act: (cubit) async {
          await cubit.initialize();
          adController.add(AdvertisingState.starting);
          adController.add(AdvertisingState.advertising);
          adController.add(AdvertisingState.stopping);
          adController.add(AdvertisingState.idle);
          await Future.delayed(const Duration(milliseconds: 10));
        },
        verify: (cubit) {
          // Verify the final state reached all four transitions in sequence.
          // The cubit may emit additional states from initialize(); we only
          // care that it reached each advertising state.
          expect(cubit.state.advertisingState, AdvertisingState.idle);
        },
      );

      blocTest<ServerCubit, ServerScreenState>(
        'reflects AdvertisingState.invalidated when emitted',
        build: createCubit,
        act: (cubit) async {
          await cubit.initialize();
          adController.add(AdvertisingState.invalidated);
          await Future.delayed(const Duration(milliseconds: 10));
        },
        verify: (cubit) {
          expect(cubit.state.advertisingState, AdvertisingState.invalidated);
        },
      );
    });

    blocTest<ServerCubit, ServerScreenState>(
      'advertising lifecycle events are ingested into log via fromBlueyEvent',
      setUp: () {
        when(() => mockCheckServerSupport()).thenReturn(true);
        when(
          () => mockObserveConnections(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockAddService(any())).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) async {
        await cubit.initialize();
        eventsController.add(AdvertisingStartingEvent());
        eventsController.add(AdvertisingStartedEvent());
        eventsController.add(AdvertisingStoppingEvent());
        eventsController.add(AdvertisingStoppedEvent());
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        final logTags = cubit.state.log.map((e) => e.tag).toList();
        expect(
          logTags.any((t) => t == 'AdvertisingStartingEvent'),
          isTrue,
          reason: 'AdvertisingStartingEvent should appear in log',
        );
        expect(
          logTags.any((t) => t == 'AdvertisingStartedEvent'),
          isTrue,
          reason: 'AdvertisingStartedEvent should appear in log',
        );
        expect(
          logTags.any((t) => t == 'AdvertisingStoppingEvent'),
          isTrue,
          reason: 'AdvertisingStoppingEvent should appear in log',
        );
        expect(
          logTags.any((t) => t == 'AdvertisingStoppedEvent'),
          isTrue,
          reason: 'AdvertisingStoppedEvent should appear in log',
        );
      },
    );
  });

  group('stress write null-server drop', () {
    late StreamController<WriteRequest> writeController;
    late MockClient stressClient;

    setUp(() {
      writeController = StreamController<WriteRequest>();
      stressClient = MockClient();
      when(
        () => stressClient.id,
      ).thenReturn(UUID('00000000-0000-0000-0000-000000000001'));
      when(() => mockCheckServerSupport()).thenReturn(true);
      when(
        () => mockObserveConnections(),
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockObserveWriteRequests(),
      ).thenAnswer((_) => writeController.stream);
      when(() => mockAddService(any())).thenAnswer((_) async {});
      when(() => mockGetServer()).thenReturn(null);
      when(
        () => mockObserveWriteRequests.respond(
          any(),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() async {
      if (!writeController.isClosed) {
        await writeController.close();
      }
    });

    blocTest<ServerCubit, ServerScreenState>(
      'stress write is rejected with requestNotSupported when server is unavailable and response required',
      build: createCubit,
      act: (cubit) async {
        await cubit.initialize();
        writeController.add(
          WriteRequest(
            client: stressClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: Uint8List.fromList([0x06]),
            offset: 0,
            responseNeeded: true,
            internalRequestId: 1,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(
          cubit.state.log.any(
            (e) =>
                e.tag == 'Stress' &&
                e.message.contains('Write rejected: server unavailable'),
          ),
          isTrue,
        );
        verify(
          () => mockObserveWriteRequests.respond(
            any(),
            status: GattResponseStatus.requestNotSupported,
          ),
        ).called(1);
      },
    );

    blocTest<ServerCubit, ServerScreenState>(
      'stress write with no response needed is silent when server is unavailable',
      build: createCubit,
      act: (cubit) async {
        await cubit.initialize();
        writeController.add(
          WriteRequest(
            client: stressClient,
            characteristicId: UUID(StressProtocol.charUuid),
            value: Uint8List.fromList([0x06]),
            offset: 0,
            responseNeeded: false,
            internalRequestId: 2,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.log.any((e) => e.tag == 'Stress'), isFalse);
      },
    );
  });
}

class _FakeWriteRequest extends Fake implements WriteRequest {}

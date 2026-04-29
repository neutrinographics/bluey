import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/connection/domain/connection_settings.dart';
import 'package:bluey_example/features/connection/presentation/connection_cubit.dart';
import 'package:bluey_example/features/connection/presentation/connection_settings_cubit.dart';
import 'package:bluey_example/features/connection/presentation/connection_state.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectToDevice mockConnectToDevice;
  late MockDisconnectDevice mockDisconnectDevice;
  late MockGetServices mockGetServices;
  late MockWatchPeer mockWatchPeer;
  late Device testDevice;

  setUpAll(() {
    registerFallbackValue(FakeDevice());
    registerFallbackValue(FakeConnection());
    registerFallbackValue(const ConnectionSettings());
  });

  setUp(() {
    mockConnectToDevice = MockConnectToDevice();
    mockDisconnectDevice = MockDisconnectDevice();
    mockGetServices = MockGetServices();
    mockWatchPeer = MockWatchPeer();
    when(() => mockWatchPeer(any()))
        .thenAnswer((_) => const Stream.empty());

    testDevice = Device(
      id: UUID('00000000-0000-0000-0000-000000000001'),
      address: '00:11:22:33:44:55',
      name: 'Test Device',
    );
  });

  ConnectionCubit createCubit({ConnectionSettingsCubit? settingsCubit}) {
    return ConnectionCubit(
      device: testDevice,
      connectToDevice: mockConnectToDevice,
      disconnectDevice: mockDisconnectDevice,
      getServices: mockGetServices,
      watchPeer: mockWatchPeer,
      settingsCubit: settingsCubit ?? ConnectionSettingsCubit(),
    );
  }

  group('ConnectionCubit', () {
    test('initial state has device and disconnected state', () {
      final cubit = createCubit();
      expect(cubit.state.device, testDevice);
      expect(cubit.state.connectionState, ConnectionState.disconnected);
      cubit.close();
    });

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'connect succeeds and auto-discovers services',
      setUp: () {
        final mockConnection = MockConnection();
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        when(
          () => mockConnection.stateChanges,
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockConnection.disconnect()).thenAnswer((_) async {});

        final mockService = MockRemoteService();

        when(
          () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
        ).thenAnswer((_) async => mockConnection);
        when(
          () => mockGetServices(any()),
        ).thenAnswer((_) async => [mockService]);
      },
      build: createCubit,
      act: (cubit) => cubit.connect(),
      expect:
          () => [
            isA<ConnectionScreenState>().having(
              (s) => s.connectionState,
              'connectionState',
              ConnectionState.connecting,
            ),
            isA<ConnectionScreenState>()
                .having(
                  (s) => s.connectionState,
                  'connectionState',
                  ConnectionState.ready,
                )
                .having((s) => s.connection, 'connection', isNotNull),
            isA<ConnectionScreenState>().having(
              (s) => s.isDiscovering,
              'isDiscovering',
              true,
            ),
            isA<ConnectionScreenState>()
                .having((s) => s.services?.length, 'services.length', 1)
                .having((s) => s.isDiscovering, 'isDiscovering', false),
          ],
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'state.peer is populated when watchPeer emits a non-null peer '
      '(stale-cache resilience: badge appears once Service Changed '
      'surfaces the lifecycle service, not just on initial discovery)',
      setUp: () {
        final mockConnection = MockConnection();
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        when(() => mockConnection.stateChanges)
            .thenAnswer((_) => const Stream.empty());
        when(() => mockConnection.disconnect()).thenAnswer((_) async {});

        final mockPeer = MockPeerConnection();
        when(() => mockPeer.disconnect()).thenAnswer((_) async {});

        when(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')))
            .thenAnswer((_) async => mockConnection);
        when(() => mockGetServices(any())).thenAnswer((_) async => []);
        // Initial null (the bug case), then a peer surfaces — exactly
        // the shape `Bluey.watchPeer` produces after a Service-Changed
        // re-discovery completes the GATT cache.
        when(() => mockWatchPeer(any())).thenAnswer((_) async* {
          yield null;
          yield mockPeer;
        });
      },
      build: createCubit,
      act: (cubit) async {
        await cubit.connect();
        // Allow the peer stream to deliver both emissions.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.peer, isNotNull);
        expect(cubit.state.isBlueyPeer, isTrue);
      },
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'connect fails and emits error',
      setUp: () {
        when(
          () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
        ).thenThrow(Exception('Connection failed'));
      },
      build: createCubit,
      act: (cubit) => cubit.connect(),
      expect:
          () => [
            isA<ConnectionScreenState>().having(
              (s) => s.connectionState,
              'connectionState',
              ConnectionState.connecting,
            ),
            isA<ConnectionScreenState>()
                .having(
                  (s) => s.connectionState,
                  'connectionState',
                  ConnectionState.disconnected,
                )
                .having((s) => s.error, 'error', isNotNull),
          ],
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'disconnect calls use case and clears connection',
      setUp: () {
        final mockConnection = MockConnection();
        when(() => mockDisconnectDevice(any())).thenAnswer((_) async {});
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        when(
          () => mockConnection.stateChanges,
        ).thenAnswer((_) => const Stream.empty());
      },
      build: () {
        final cubit = createCubit();
        // Manually set connected state
        return cubit;
      },
      seed: () {
        final mockConnection = MockConnection();
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        return ConnectionScreenState(
          device: testDevice,
          connection: mockConnection,
          connectionState: ConnectionState.ready,
        );
      },
      act: (cubit) => cubit.disconnect(),
      expect:
          () => [
            isA<ConnectionScreenState>()
                .having((s) => s.connection, 'connection', isNull)
                .having(
                  (s) => s.connectionState,
                  'connectionState',
                  ConnectionState.disconnected,
                ),
          ],
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'clearError clears the error',
      build: createCubit,
      seed:
          () => ConnectionScreenState(
            device: testDevice,
            connectionState: ConnectionState.disconnected,
            error: 'Some error',
          ),
      act: (cubit) => cubit.clearError(),
      expect:
          () => [
            isA<ConnectionScreenState>().having(
              (s) => s.error,
              'error',
              isNull,
            ),
          ],
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'disconnect emits error when disconnect fails',
      setUp: () {
        when(
          () => mockDisconnectDevice(any()),
        ).thenThrow(Exception('Disconnect failed'));
      },
      build: createCubit,
      seed: () {
        final mockConnection = MockConnection();
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        when(() => mockConnection.disconnect()).thenAnswer((_) async {});
        return ConnectionScreenState(
          device: testDevice,
          connection: mockConnection,
          connectionState: ConnectionState.ready,
        );
      },
      act: (cubit) => cubit.disconnect(),
      expect:
          () => [
            isA<ConnectionScreenState>().having(
              (s) => s.error,
              'error',
              contains('Failed to disconnect'),
            ),
          ],
    );

    blocTest<ConnectionCubit, ConnectionScreenState>(
      'connect emits error when connection state stream errors',
      setUp: () {
        final mockConnection = MockConnection();
        when(() => mockConnection.state).thenReturn(ConnectionState.ready);
        // Use async* to emit error after a microtask delay
        when(() => mockConnection.stateChanges).thenAnswer((_) async* {
          await Future.delayed(Duration.zero);
          throw Exception('State stream error');
        });
        when(() => mockConnection.disconnect()).thenAnswer((_) async {});

        when(
          () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
        ).thenAnswer((_) async => mockConnection);
        when(() => mockGetServices(any())).thenAnswer((_) async => []);
      },
      build: createCubit,
      act: (cubit) async {
        await cubit.connect();
        // Allow stream error to propagate
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        // Verify that the error was emitted at some point
        expect(cubit.state.error, contains('Connection state error'));
      },
    );

    test('reconnects when settings change while connected', () async {
      final settingsCubit = ConnectionSettingsCubit();

      final firstConn = MockConnection();
      when(() => firstConn.state).thenReturn(ConnectionState.ready);
      when(() => firstConn.stateChanges)
          .thenAnswer((_) => const Stream.empty());
      when(() => firstConn.disconnect()).thenAnswer((_) async {});

      final secondConn = MockConnection();
      when(() => secondConn.state).thenReturn(ConnectionState.ready);
      when(() => secondConn.stateChanges)
          .thenAnswer((_) => const Stream.empty());
      when(() => secondConn.disconnect()).thenAnswer((_) async {});

      when(() => mockDisconnectDevice(any())).thenAnswer((_) async {});
      when(() => mockGetServices(any())).thenAnswer((_) async => []);

      final connections = [firstConn, secondConn];
      when(
        () => mockConnectToDevice(
          any(),
          timeout: any(named: 'timeout'),
          settings: any(named: 'settings'),
        ),
      ).thenAnswer((_) async => connections.removeAt(0));

      final cubit = createCubit(settingsCubit: settingsCubit);
      await cubit.connect();
      expect(cubit.state.connection, isNotNull);

      // Change tolerance → cubit observes settings change → reconnects.
      settingsCubit.setPeerSilenceTimeout(const Duration(seconds: 60));
      // Allow the async reconnect chain to drain (disconnect + connect + loadServices).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => mockDisconnectDevice(any())).called(1);
      verify(
        () => mockConnectToDevice(
          any(),
          timeout: any(named: 'timeout'),
          settings: any(named: 'settings'),
        ),
      ).called(2);

      await cubit.close();
    });

    test('no reconnect when settings unchanged', () async {
      final settingsCubit = ConnectionSettingsCubit();

      final mockConn = MockConnection();
      when(() => mockConn.state).thenReturn(ConnectionState.ready);
      when(() => mockConn.stateChanges)
          .thenAnswer((_) => const Stream.empty());
      when(() => mockConn.disconnect()).thenAnswer((_) async {});

      when(
        () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => mockConn);
      when(() => mockGetServices(any())).thenAnswer((_) async => []);

      final cubit = createCubit(settingsCubit: settingsCubit);
      await cubit.connect();

      // Same value → no-op.
      settingsCubit.setPeerSilenceTimeout(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockDisconnectDevice(any()));
      verify(() => mockConnectToDevice(any(), timeout: any(named: 'timeout')))
          .called(1);

      await cubit.close();
    });

    test('settings change while disconnected does not trigger connect',
        () async {
      final settingsCubit = ConnectionSettingsCubit();
      final cubit = createCubit(settingsCubit: settingsCubit);

      // Don't call connect(). Change settings.
      settingsCubit.setPeerSilenceTimeout(const Duration(seconds: 60));
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockConnectToDevice(any(), timeout: any(named: 'timeout')),
      );

      await cubit.close();
    });
  });
}

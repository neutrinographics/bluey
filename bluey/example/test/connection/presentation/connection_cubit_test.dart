import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/connection/presentation/connection_cubit.dart';
import 'package:bluey_example/features/connection/presentation/connection_state.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectToDevice mockConnectToDevice;
  late MockDisconnectDevice mockDisconnectDevice;
  late MockGetServices mockGetServices;
  late Device testDevice;

  setUpAll(() {
    registerFallbackValue(FakeDevice());
    registerFallbackValue(FakeConnection());
  });

  setUp(() {
    mockConnectToDevice = MockConnectToDevice();
    mockDisconnectDevice = MockDisconnectDevice();
    mockGetServices = MockGetServices();

    testDevice = Device(
      id: UUID('00000000-0000-0000-0000-000000000001'),
      address: '00:11:22:33:44:55',
      name: 'Test Device',
      rssi: -50,
      advertisement: Advertisement.empty(),
      lastSeen: DateTime.now(),
    );
  });

  ConnectionCubit createCubit() {
    return ConnectionCubit(
      device: testDevice,
      connectToDevice: mockConnectToDevice,
      disconnectDevice: mockDisconnectDevice,
      getServices: mockGetServices,
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
        when(() => mockConnection.state).thenReturn(ConnectionState.connected);
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
                  ConnectionState.connected,
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
        when(() => mockConnection.state).thenReturn(ConnectionState.connected);
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
        when(() => mockConnection.state).thenReturn(ConnectionState.connected);
        return ConnectionScreenState(
          device: testDevice,
          connection: mockConnection,
          connectionState: ConnectionState.connected,
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
        when(() => mockConnection.state).thenReturn(ConnectionState.connected);
        when(() => mockConnection.disconnect()).thenAnswer((_) async {});
        return ConnectionScreenState(
          device: testDevice,
          connection: mockConnection,
          connectionState: ConnectionState.connected,
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
        when(() => mockConnection.state).thenReturn(ConnectionState.connected);
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
  });
}

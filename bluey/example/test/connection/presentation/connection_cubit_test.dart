import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/connection/presentation/connection_cubit.dart';
import 'package:bluey_example/connection/presentation/connection_state.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectToDevice mockConnectToDevice;
  late MockDisconnectDevice mockDisconnectDevice;
  late MockDiscoverServices mockDiscoverServices;
  late Device testDevice;

  setUpAll(() {
    registerFallbackValue(FakeDevice());
    registerFallbackValue(FakeConnection());
  });

  setUp(() {
    mockConnectToDevice = MockConnectToDevice();
    mockDisconnectDevice = MockDisconnectDevice();
    mockDiscoverServices = MockDiscoverServices();

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
      discoverServices: mockDiscoverServices,
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
          () => mockDiscoverServices(any()),
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
  });
}

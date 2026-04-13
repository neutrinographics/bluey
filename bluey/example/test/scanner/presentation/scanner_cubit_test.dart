import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/scanner/presentation/scanner_cubit.dart';
import 'package:bluey_example/features/scanner/presentation/scanner_state.dart';

import '../../mocks/mock_use_cases.dart';

void main() {
  late MockScanForDevices mockScanForDevices;
  late MockStopScan mockStopScan;
  late MockGetBluetoothState mockGetBluetoothState;
  late MockRequestPermissions mockRequestPermissions;
  late MockRequestEnable mockRequestEnable;

  setUp(() {
    mockScanForDevices = MockScanForDevices();
    mockStopScan = MockStopScan();
    mockGetBluetoothState = MockGetBluetoothState();
    mockRequestPermissions = MockRequestPermissions();
    mockRequestEnable = MockRequestEnable();
  });

  ScannerCubit createCubit() {
    return ScannerCubit(
      scanForDevices: mockScanForDevices,
      stopScan: mockStopScan,
      getBluetoothState: mockGetBluetoothState,
      requestPermissions: mockRequestPermissions,
      requestEnable: mockRequestEnable,
    );
  }

  group('ScannerCubit', () {
    test('initial state is correct', () {
      when(
        () => mockGetBluetoothState.current,
      ).thenReturn(BluetoothState.unknown);
      when(
        () => mockGetBluetoothState(),
      ).thenAnswer((_) => const Stream.empty());

      final cubit = createCubit();
      expect(cubit.state, const ScannerState());
      cubit.close();
    });

    blocTest<ScannerCubit, ScannerState>(
      'initialize sets bluetooth state and listens to changes',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(() => mockGetBluetoothState()).thenAnswer(
          (_) => Stream.fromIterable([BluetoothState.off, BluetoothState.on]),
        );
      },
      build: createCubit,
      act: (cubit) => cubit.initialize(),
      expect:
          () => [
            const ScannerState(bluetoothState: BluetoothState.on),
            const ScannerState(bluetoothState: BluetoothState.off),
            const ScannerState(bluetoothState: BluetoothState.on),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'startScan emits error when bluetooth is not ready',
      setUp: () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.off);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
      },
      build: createCubit,
      seed: () => const ScannerState(bluetoothState: BluetoothState.off),
      act: (cubit) => cubit.startScan(),
      expect:
          () => [
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Bluetooth is not ready'),
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'startScan emits devices when bluetooth is ready',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());

        final scanResult = ScanResult(
          device: Device(
            id: UUID('00000000-0000-0000-0000-000000000001'),
            address: '00:11:22:33:44:55',
            name: 'Test Device',
          ),
          rssi: -50,
          advertisement: Advertisement.empty(),
          lastSeen: DateTime.now(),
        );

        when(
          () => mockScanForDevices(timeout: any(named: 'timeout')),
        ).thenAnswer((_) => Stream.value(scanResult));
      },
      build: createCubit,
      seed: () => const ScannerState(bluetoothState: BluetoothState.on),
      act: (cubit) => cubit.startScan(),
      expect:
          () => [
            const ScannerState(
              bluetoothState: BluetoothState.on,
              scanResults: [],
              isScanning: true,
            ),
            isA<ScannerState>()
                .having((s) => s.scanResults.length, 'scanResults.length', 1)
                .having(
                  (s) => s.scanResults.first.device.name,
                  'first device name',
                  'Test Device',
                ),
            isA<ScannerState>().having(
              (s) => s.isScanning,
              'isScanning',
              false,
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'stopScan stops scanning',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockStopScan()).thenAnswer((_) async {});
      },
      build: createCubit,
      seed:
          () => const ScannerState(
            bluetoothState: BluetoothState.on,
            isScanning: true,
          ),
      act: (cubit) => cubit.stopScan(),
      expect:
          () => [
            const ScannerState(
              bluetoothState: BluetoothState.on,
              isScanning: false,
            ),
          ],
      verify: (_) {
        verify(() => mockStopScan()).called(1);
      },
    );

    blocTest<ScannerCubit, ScannerState>(
      'requestPermissions returns result and emits error on denial',
      setUp: () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.unauthorized);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockRequestPermissions()).thenAnswer((_) async => false);
      },
      build: createCubit,
      act: (cubit) async {
        final result = await cubit.requestPermissions();
        expect(result, false);
      },
      expect:
          () => [
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Permission denied'),
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'clearError clears the error',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
      },
      build: createCubit,
      seed:
          () => const ScannerState(
            bluetoothState: BluetoothState.on,
            error: 'Some error',
          ),
      act: (cubit) => cubit.clearError(),
      expect: () => [const ScannerState(bluetoothState: BluetoothState.on)],
    );

    blocTest<ScannerCubit, ScannerState>(
      'stopScan emits error when stop fails',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockStopScan()).thenThrow(Exception('Stop failed'));
      },
      build: createCubit,
      seed:
          () => const ScannerState(
            bluetoothState: BluetoothState.on,
            isScanning: true,
          ),
      act: (cubit) => cubit.stopScan(),
      expect:
          () => [
            isA<ScannerState>()
                .having((s) => s.isScanning, 'isScanning', false)
                .having(
                  (s) => s.error,
                  'error',
                  contains('Failed to stop scan'),
                ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'requestEnable emits error when enable fails',
      setUp: () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.off);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(() => mockRequestEnable()).thenThrow(Exception('Enable failed'));
      },
      build: createCubit,
      act: (cubit) => cubit.requestEnable(),
      expect:
          () => [
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Failed to enable Bluetooth'),
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'openSettings emits error when open fails',
      setUp: () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.off);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(
          () => mockRequestEnable.openSettings(),
        ).thenThrow(Exception('Settings failed'));
      },
      build: createCubit,
      act: (cubit) => cubit.openSettings(),
      expect:
          () => [
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Failed to open settings'),
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'requestPermissions emits error when request throws',
      setUp: () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.unauthorized);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());
        when(
          () => mockRequestPermissions(),
        ).thenThrow(Exception('Permission error'));
      },
      build: createCubit,
      act: (cubit) async {
        final result = await cubit.requestPermissions();
        expect(result, false);
      },
      expect:
          () => [
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Failed to request permissions'),
            ),
          ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'initialize emits error when bluetooth state stream errors',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => Stream.error(Exception('State stream error')));
      },
      build: createCubit,
      act: (cubit) => cubit.initialize(),
      expect:
          () => [
            const ScannerState(bluetoothState: BluetoothState.on),
            isA<ScannerState>().having(
              (s) => s.error,
              'error',
              contains('Bluetooth state error'),
            ),
          ],
    );
  });
}

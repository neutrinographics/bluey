import 'dart:async';

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
      'startScan sets isScanning false when stream completes',
      setUp: () {
        when(() => mockGetBluetoothState.current).thenReturn(BluetoothState.on);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());

        // Stream that emits one result then completes (as the library now does)
        final result = ScanResult(
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
        ).thenAnswer((_) => Stream.value(result));
      },
      build: createCubit,
      seed: () => const ScannerState(bluetoothState: BluetoothState.on),
      act: (cubit) => cubit.startScan(),
      expect: () => [
        const ScannerState(
          bluetoothState: BluetoothState.on,
          scanResults: [],
          isScanning: true,
        ),
        isA<ScannerState>()
            .having((s) => s.scanResults.length, 'scanResults.length', 1)
            .having((s) => s.isScanning, 'isScanning', true),
        isA<ScannerState>().having(
          (s) => s.isScanning,
          'isScanning',
          false,
        ),
      ],
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

    group('sorting', () {
      final deviceA = ScanResult(
        device: Device(
          id: UUID('00000000-0000-0000-0000-000000000001'),
          address: '00:11:22:33:44:55',
          name: 'Alpha Device',
        ),
        rssi: -80,
        advertisement: Advertisement.empty(),
        lastSeen: DateTime(2024),
      );

      final deviceB = ScanResult(
        device: Device(
          id: UUID('00000000-0000-0000-0000-000000000002'),
          address: 'AA:BB:CC:DD:EE:FF',
          name: 'Beta Device',
        ),
        rssi: -40,
        advertisement: Advertisement.empty(),
        lastSeen: DateTime(2024),
      );

      final unnamed = ScanResult(
        device: Device(
          id: UUID('00000000-0000-0000-0000-000000000003'),
          address: 'FF:FF:FF:FF:FF:FF',
        ),
        rssi: -60,
        advertisement: Advertisement.empty(),
        lastSeen: DateTime(2024),
      );

      test('initial sort mode is signalStrength', () {
        when(
          () => mockGetBluetoothState.current,
        ).thenReturn(BluetoothState.unknown);
        when(
          () => mockGetBluetoothState(),
        ).thenAnswer((_) => const Stream.empty());

        final cubit = createCubit();
        expect(cubit.state.sortMode, SortMode.signalStrength);
        cubit.close();
      });

      blocTest<ScannerCubit, ScannerState>(
        'setSortMode emits state with new sort mode',
        setUp: () {
          when(
            () => mockGetBluetoothState.current,
          ).thenReturn(BluetoothState.on);
          when(
            () => mockGetBluetoothState(),
          ).thenAnswer((_) => const Stream.empty());
        },
        build: createCubit,
        seed: () => ScannerState(
          bluetoothState: BluetoothState.on,
          scanResults: [deviceB, deviceA],
        ),
        act: (cubit) => cubit.setSortMode(SortMode.name),
        expect: () => [
          isA<ScannerState>().having(
            (s) => s.sortMode,
            'sortMode',
            SortMode.name,
          ),
        ],
      );

      blocTest<ScannerCubit, ScannerState>(
        'sort by name orders alphabetically',
        setUp: () {
          when(
            () => mockGetBluetoothState.current,
          ).thenReturn(BluetoothState.on);
          when(
            () => mockGetBluetoothState(),
          ).thenAnswer((_) => const Stream.empty());
        },
        build: createCubit,
        seed: () => ScannerState(
          bluetoothState: BluetoothState.on,
          scanResults: [deviceB, deviceA],
        ),
        act: (cubit) => cubit.setSortMode(SortMode.name),
        expect: () => [
          isA<ScannerState>().having(
            (s) => s.scanResults.map((r) => r.device.name).toList(),
            'device names',
            ['Alpha Device', 'Beta Device'],
          ),
        ],
      );

      blocTest<ScannerCubit, ScannerState>(
        'sort by name places unnamed devices last',
        setUp: () {
          when(
            () => mockGetBluetoothState.current,
          ).thenReturn(BluetoothState.on);
          when(
            () => mockGetBluetoothState(),
          ).thenAnswer((_) => const Stream.empty());
        },
        build: createCubit,
        seed: () => ScannerState(
          bluetoothState: BluetoothState.on,
          scanResults: [unnamed, deviceA],
        ),
        act: (cubit) => cubit.setSortMode(SortMode.name),
        expect: () => [
          isA<ScannerState>().having(
            (s) => s.scanResults.map((r) => r.device.name).toList(),
            'device names',
            ['Alpha Device', null],
          ),
        ],
      );

      blocTest<ScannerCubit, ScannerState>(
        'sort by signalStrength orders by RSSI descending',
        setUp: () {
          when(
            () => mockGetBluetoothState.current,
          ).thenReturn(BluetoothState.on);
          when(
            () => mockGetBluetoothState(),
          ).thenAnswer((_) => const Stream.empty());
        },
        build: createCubit,
        seed: () => ScannerState(
          bluetoothState: BluetoothState.on,
          sortMode: SortMode.name,
          scanResults: [deviceA, deviceB],
        ),
        act: (cubit) => cubit.setSortMode(SortMode.signalStrength),
        expect: () => [
          isA<ScannerState>().having(
            (s) => s.scanResults.map((r) => r.rssi).toList(),
            'rssi values',
            [-40, -80],
          ),
        ],
      );

      blocTest<ScannerCubit, ScannerState>(
        'sort by deviceId orders by UUID string',
        setUp: () {
          when(
            () => mockGetBluetoothState.current,
          ).thenReturn(BluetoothState.on);
          when(
            () => mockGetBluetoothState(),
          ).thenAnswer((_) => const Stream.empty());
        },
        build: createCubit,
        seed: () => ScannerState(
          bluetoothState: BluetoothState.on,
          scanResults: [deviceB, deviceA],
        ),
        act: (cubit) => cubit.setSortMode(SortMode.deviceId),
        expect: () => [
          isA<ScannerState>().having(
            (s) => s.scanResults.map((r) => r.device.id.toString()).toList(),
            'device ids',
            [
              '00000000-0000-0000-0000-000000000001',
              '00000000-0000-0000-0000-000000000002',
            ],
          ),
        ],
      );
    });
  });
}

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/scanner/presentation/scanner_cubit.dart';
import 'package:bluey_example/features/scanner/presentation/scanner_state.dart';

import '../../mocks/mock_bluey.dart';
import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_use_cases.dart';

class _MockScanner extends Mock implements Scanner {}

void main() {
  late MockScanForDevices mockScanForDevices;
  late MockGetBluetoothState mockGetBluetoothState;
  late MockRequestPermissions mockRequestPermissions;
  late MockRequestEnable mockRequestEnable;
  late MockBluey mockBluey;
  late MockScannerRepository mockRepository;
  late _MockScanner mockScanner;
  late StreamController<ScanState> scanStateController;
  late StreamController<BlueyEvent> eventsController;

  setUp(() {
    mockScanForDevices = MockScanForDevices();
    mockGetBluetoothState = MockGetBluetoothState();
    mockRequestPermissions = MockRequestPermissions();
    mockRequestEnable = MockRequestEnable();
    mockBluey = MockBluey();
    mockRepository = MockScannerRepository();
    mockScanner = _MockScanner();
    scanStateController = StreamController<ScanState>.broadcast();
    eventsController = StreamController<BlueyEvent>.broadcast();

    // The repository exposes the SAME shared scanner — this is the core
    // invariant the two-scanner fix enforces. Both the cubit (via
    // repository.scanner) and the use-case (via repository.scan()) now
    // go through the same object.
    when(() => mockRepository.scanner).thenReturn(mockScanner);
    when(() => mockBluey.events).thenAnswer((_) => eventsController.stream);
    when(() => mockScanner.stateChanges)
        .thenAnswer((_) => scanStateController.stream);
    when(() => mockGetBluetoothState())
        .thenAnswer((_) => const Stream.empty());
    when(() => mockGetBluetoothState.current)
        .thenReturn(BluetoothState.on);
  });

  tearDown(() async {
    await scanStateController.close();
    await eventsController.close();
  });

  ScannerCubit createCubit() {
    return ScannerCubit(
      scanForDevices: mockScanForDevices,
      getBluetoothState: mockGetBluetoothState,
      requestPermissions: mockRequestPermissions,
      requestEnable: mockRequestEnable,
      repository: mockRepository,
      bluey: mockBluey,
    );
  }

  group('ScannerCubit', () {
    // P1: Eager scanner creation crashes when BT off
    test(
      'initialize() does not access scanner when BT is off',
      () async {
        // Override BT state to emit off — scanner must NOT be accessed.
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => Stream.value(BluetoothState.off));
        when(() => mockGetBluetoothState.current)
            .thenReturn(BluetoothState.off);
        // Intentionally do NOT stub mockRepository.scanner so that any
        // access throws a MissingStubError (mocktail's noSuchMethod).

        final cubit = createCubit();
        cubit.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(cubit.state.bluetoothState, BluetoothState.off);
        verifyNever(() => mockRepository.scanner);
        await cubit.close();
      },
    );

    blocTest<ScannerCubit, ScannerState>(
      'attaches scanner subscription when BT transitions to on',
      setUp: () {
        final btController = StreamController<BluetoothState>();
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => btController.stream);
        when(() => mockGetBluetoothState.current)
            .thenReturn(BluetoothState.off);
        // Emit off then on inside act via the controller captured here.
        // We add events in act through a fresh controller, so store it
        // on the stream stub.
        addTearDown(btController.close);
        // Emit off → on
        btController.add(BluetoothState.off);
        btController.add(BluetoothState.on);
      },
      build: createCubit,
      act: (cubit) async {
        cubit.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.bluetoothState, BluetoothState.on);
        // repository.scanner should have been called to attach the
        // scanner-state subscription once BT turned on.
        verify(() => mockRepository.scanner).called(greaterThanOrEqualTo(1));
      },
    );

    // P2: Missing onError on scan stream
    blocTest<ScannerCubit, ScannerState>(
      'scan stream error surfaces to state.error',
      setUp: () {
        // BT is on so initialize() can attach the scanner subscription.
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => Stream.value(BluetoothState.on));
        when(() => mockGetBluetoothState.current)
            .thenReturn(BluetoothState.on);
        // Arrange scan() to return a stream that immediately emits an error.
        when(() => mockScanForDevices(timeout: any(named: 'timeout')))
            .thenAnswer(
              (_) => Stream.error(Exception('native scan failed')),
            );
      },
      build: createCubit,
      act: (cubit) async {
        cubit.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        cubit.startScan();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.error, contains('Scan error'));
      },
    );

    test('initial state has stopped scanState and empty scanLog', () {
      final cubit = createCubit();
      expect(cubit.state.scanState, ScanState.stopped);
      expect(cubit.state.scanLog, isEmpty);
      cubit.close();
    });

    test(
      'initialize() subscribes to scanner via repository (not via Bluey.scanner())',
      () async {
        // BT must be on for the lazy attach to trigger.
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => Stream.value(BluetoothState.on));
        final cubit = createCubit();
        cubit.initialize();
        // Allow the BT state event to propagate before verifying.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        // The repository.scanner getter must have been accessed; Bluey.scanner()
        // must NOT have been called directly (that would create a second instance).
        verify(() => mockRepository.scanner).called(greaterThanOrEqualTo(1));
        verifyNever(() => mockBluey.scanner());
        await cubit.close();
      },
    );

    blocTest<ScannerCubit, ScannerState>(
      'reflects ScanState transitions from scanner.stateChanges',
      // BT must be on so the scanner subscription is attached before we emit
      // scan state events.
      setUp: () {
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => Stream.value(BluetoothState.on));
      },
      build: createCubit,
      act: (cubit) async {
        cubit.initialize();
        // Allow the BT on event to propagate and attach the scanner sub.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        scanStateController.add(ScanState.starting);
        scanStateController.add(ScanState.scanning);
        scanStateController.add(ScanState.stopping);
        scanStateController.add(ScanState.stopped);
      },
      expect: () => [
        // BT.on causes a bluetoothState emit; subsequent scan state changes
        // are appended in order.
        isA<ScannerState>()
            .having((s) => s.bluetoothState, 'bluetoothState', BluetoothState.on),
        isA<ScannerState>()
            .having((s) => s.scanState, 'scanState', ScanState.starting),
        isA<ScannerState>()
            .having((s) => s.scanState, 'scanState', ScanState.scanning),
        isA<ScannerState>()
            .having((s) => s.scanState, 'scanState', ScanState.stopping),
        isA<ScannerState>()
            .having((s) => s.scanState, 'scanState', ScanState.stopped),
      ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'reflects ScanState.invalidated when emitted',
      // BT must be on so the scanner subscription is attached.
      setUp: () {
        when(() => mockGetBluetoothState())
            .thenAnswer((_) => Stream.value(BluetoothState.on));
      },
      build: createCubit,
      act: (cubit) async {
        cubit.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        scanStateController.add(ScanState.invalidated);
      },
      expect: () => [
        isA<ScannerState>()
            .having((s) => s.bluetoothState, 'bluetoothState', BluetoothState.on),
        isA<ScannerState>()
            .having((s) => s.scanState, 'scanState', ScanState.invalidated),
      ],
    );

    blocTest<ScannerCubit, ScannerState>(
      'appends scan lifecycle events into scanLog',
      build: createCubit,
      act: (cubit) {
        cubit.initialize();
        eventsController.add(ScanStartingEvent(source: 'test'));
        eventsController.add(ScanStartedEvent(source: 'test'));
        eventsController.add(ScanStoppingEvent(source: 'test'));
        eventsController.add(ScanStoppedEvent(source: 'test'));
      },
      verify: (cubit) {
        expect(cubit.state.scanLog.length, equals(4));
        expect(cubit.state.scanLog.first, isA<ScanStartingEvent>());
        expect(cubit.state.scanLog.last, isA<ScanStoppedEvent>());
      },
    );

    blocTest<ScannerCubit, ScannerState>(
      'appends DeviceDiscoveredEvent into scanLog',
      build: createCubit,
      act: (cubit) {
        cubit.initialize();
        eventsController.add(
          DeviceDiscoveredEvent(
            deviceId: UUID('00000000-0000-0000-0000-000000000001'),
            name: 'Test Device',
            rssi: -70,
          ),
        );
      },
      verify: (cubit) {
        expect(cubit.state.scanLog.length, equals(1));
        expect(cubit.state.scanLog.first, isA<DeviceDiscoveredEvent>());
      },
    );

    blocTest<ScannerCubit, ScannerState>(
      'caps scanLog at 100 entries',
      build: createCubit,
      act: (cubit) {
        cubit.initialize();
        for (var i = 0; i < 150; i++) {
          eventsController.add(ScanStartingEvent(source: 'test'));
        }
      },
      verify: (cubit) {
        expect(cubit.state.scanLog.length, equals(100));
      },
    );
  });
}

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/scanner/presentation/scanner_cubit.dart';
import 'package:bluey_example/features/scanner/presentation/scanner_state.dart';

import '../../mocks/mock_bluey.dart';
import '../../mocks/mock_use_cases.dart';

class _MockScanner extends Mock implements Scanner {}

void main() {
  late MockScanForDevices mockScanForDevices;
  late MockGetBluetoothState mockGetBluetoothState;
  late MockRequestPermissions mockRequestPermissions;
  late MockRequestEnable mockRequestEnable;
  late MockBluey mockBluey;
  late _MockScanner mockScanner;
  late StreamController<ScanState> scanStateController;
  late StreamController<BlueyEvent> eventsController;

  setUp(() {
    mockScanForDevices = MockScanForDevices();
    mockGetBluetoothState = MockGetBluetoothState();
    mockRequestPermissions = MockRequestPermissions();
    mockRequestEnable = MockRequestEnable();
    mockBluey = MockBluey();
    mockScanner = _MockScanner();
    scanStateController = StreamController<ScanState>.broadcast();
    eventsController = StreamController<BlueyEvent>.broadcast();

    when(() => mockBluey.scanner()).thenReturn(mockScanner);
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
      bluey: mockBluey,
    );
  }

  group('ScannerCubit', () {
    test('initial state has stopped scanState and empty scanLog', () {
      final cubit = createCubit();
      expect(cubit.state.scanState, ScanState.stopped);
      expect(cubit.state.scanLog, isEmpty);
      cubit.close();
    });

    blocTest<ScannerCubit, ScannerState>(
      'reflects ScanState transitions from scanner.stateChanges',
      build: createCubit,
      act: (cubit) {
        cubit.initialize();
        scanStateController.add(ScanState.starting);
        scanStateController.add(ScanState.scanning);
        scanStateController.add(ScanState.stopping);
        scanStateController.add(ScanState.stopped);
      },
      expect: () => [
        // initialize() may or may not emit; use the matcher to verify
        // the cubit reaches each scanState in order regardless of any
        // intermediate emissions.
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
      build: createCubit,
      act: (cubit) {
        cubit.initialize();
        scanStateController.add(ScanState.invalidated);
      },
      expect: () => [
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

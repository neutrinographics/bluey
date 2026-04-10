import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/service_explorer/presentation/service_cubit.dart';
import 'package:bluey_example/features/service_explorer/presentation/service_state.dart';

import '../../mocks/mock_use_cases.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockReadCharacteristic mockReadCharacteristic;
  late MockWriteCharacteristic mockWriteCharacteristic;
  late MockSubscribeToCharacteristic mockSubscribeToCharacteristic;
  late MockReadDescriptor mockReadDescriptor;
  late MockRemoteCharacteristic mockCharacteristic;

  setUpAll(() {
    registerFallbackValue(FakeRemoteCharacteristic());
    registerFallbackValue(FakeRemoteDescriptor());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockReadCharacteristic = MockReadCharacteristic();
    mockWriteCharacteristic = MockWriteCharacteristic();
    mockSubscribeToCharacteristic = MockSubscribeToCharacteristic();
    mockReadDescriptor = MockReadDescriptor();
    mockCharacteristic = MockRemoteCharacteristic();

    when(() => mockCharacteristic.properties).thenReturn(
      const CharacteristicProperties(
        canRead: true,
        canWrite: true,
        canNotify: true,
      ),
    );
    when(() => mockCharacteristic.descriptors).thenReturn([]);
  });

  CharacteristicCubit createCubit() {
    return CharacteristicCubit(
      characteristic: mockCharacteristic,
      readCharacteristic: mockReadCharacteristic,
      writeCharacteristic: mockWriteCharacteristic,
      subscribeToCharacteristic: mockSubscribeToCharacteristic,
      readDescriptor: mockReadDescriptor,
    );
  }

  group('CharacteristicCubit', () {
    test('initial state has characteristic and defaults', () {
      final cubit = createCubit();
      expect(cubit.state.characteristic, mockCharacteristic);
      expect(cubit.state.value, isNull);
      expect(cubit.state.isReading, isFalse);
      expect(cubit.state.isWriting, isFalse);
      expect(cubit.state.isSubscribed, isFalse);
      expect(cubit.state.log, isEmpty);
      expect(cubit.state.error, isNull);
      cubit.close();
    });

    blocTest<CharacteristicCubit, CharacteristicState>(
      'read succeeds and updates value and log',
      setUp: () {
        final data = Uint8List.fromList([0x01, 0x02]);
        when(() => mockReadCharacteristic(any()))
            .thenAnswer((_) async => data);
      },
      build: createCubit,
      act: (cubit) => cubit.read(),
      expect: () => [
        isA<CharacteristicState>()
            .having((s) => s.isReading, 'isReading', true)
            .having((s) => s.error, 'error', isNull),
        isA<CharacteristicState>()
            .having((s) => s.isReading, 'isReading', false)
            .having((s) => s.value, 'value', Uint8List.fromList([0x01, 0x02]))
            .having((s) => s.log.length, 'log.length', 1)
            .having((s) => s.log.first.operation, 'log[0].operation', 'Read'),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'read emits error on failure',
      setUp: () {
        when(() => mockReadCharacteristic(any()))
            .thenThrow(Exception('Read error'));
      },
      build: createCubit,
      act: (cubit) => cubit.read(),
      expect: () => [
        isA<CharacteristicState>().having((s) => s.isReading, 'isReading', true),
        isA<CharacteristicState>()
            .having((s) => s.isReading, 'isReading', false)
            .having((s) => s.error, 'error', contains('Read failed')),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'write succeeds and adds log entry',
      setUp: () {
        when(
          () => mockWriteCharacteristic(
            any(),
            any(),
            withResponse: any(named: 'withResponse'),
          ),
        ).thenAnswer((_) async {});
      },
      build: createCubit,
      act: (cubit) => cubit.write(Uint8List.fromList([0xAA])),
      expect: () => [
        isA<CharacteristicState>()
            .having((s) => s.isWriting, 'isWriting', true)
            .having((s) => s.error, 'error', isNull),
        isA<CharacteristicState>()
            .having((s) => s.isWriting, 'isWriting', false)
            .having((s) => s.log.length, 'log.length', 1)
            .having((s) => s.log.first.operation, 'log[0].operation', 'Write'),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'write emits error on failure',
      setUp: () {
        when(
          () => mockWriteCharacteristic(
            any(),
            any(),
            withResponse: any(named: 'withResponse'),
          ),
        ).thenThrow(Exception('Write error'));
      },
      build: createCubit,
      act: (cubit) => cubit.write(Uint8List.fromList([0xAA])),
      expect: () => [
        isA<CharacteristicState>().having((s) => s.isWriting, 'isWriting', true),
        isA<CharacteristicState>()
            .having((s) => s.isWriting, 'isWriting', false)
            .having((s) => s.error, 'error', contains('Write failed')),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'toggleNotifications subscribes and emits isSubscribed true',
      setUp: () {
        when(() => mockSubscribeToCharacteristic(any()))
            .thenAnswer((_) => const Stream.empty());
      },
      build: createCubit,
      act: (cubit) => cubit.toggleNotifications(),
      expect: () => [
        isA<CharacteristicState>().having(
          (s) => s.isSubscribed,
          'isSubscribed',
          true,
        ),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'toggleNotifications unsubscribes when already subscribed',
      setUp: () {
        when(() => mockSubscribeToCharacteristic(any()))
            .thenAnswer((_) => const Stream.empty());
      },
      build: createCubit,
      act: (cubit) {
        // Subscribe first, then unsubscribe
        cubit.toggleNotifications();
        cubit.toggleNotifications();
      },
      expect: () => [
        isA<CharacteristicState>().having(
          (s) => s.isSubscribed,
          'isSubscribed',
          true,
        ),
        isA<CharacteristicState>().having(
          (s) => s.isSubscribed,
          'isSubscribed',
          false,
        ),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'notification stream updates value and log',
      setUp: () {
        final controller = StreamController<Uint8List>();
        when(() => mockSubscribeToCharacteristic(any()))
            .thenAnswer((_) => controller.stream);
        // Schedule data emission after subscription
        Future.microtask(() {
          controller.add(Uint8List.fromList([0x42]));
          controller.close();
        });
      },
      build: createCubit,
      act: (cubit) async {
        cubit.toggleNotifications();
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.value, Uint8List.fromList([0x42]));
        expect(
          cubit.state.log.any((e) => e.operation == 'Notify'),
          isTrue,
        );
      },
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'notification stream error sets isSubscribed false',
      setUp: () {
        when(() => mockSubscribeToCharacteristic(any()))
            .thenAnswer((_) => Stream.error(Exception('Stream error')));
      },
      build: createCubit,
      act: (cubit) async {
        cubit.toggleNotifications();
        await Future.delayed(const Duration(milliseconds: 10));
      },
      verify: (cubit) {
        expect(cubit.state.isSubscribed, isFalse);
        expect(cubit.state.error, contains('Notification error'));
      },
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'readDescriptor succeeds and stores value',
      setUp: () {
        final descriptor = MockRemoteDescriptor();
        when(() => descriptor.uuid).thenReturn(
          UUID('00002902-0000-1000-8000-00805f9b34fb'),
        );
        when(() => mockReadDescriptor(any()))
            .thenAnswer((_) async => Uint8List.fromList([0x01, 0x00]));
      },
      build: createCubit,
      act: (cubit) {
        final descriptor = MockRemoteDescriptor();
        when(() => descriptor.uuid).thenReturn(
          UUID('00002902-0000-1000-8000-00805f9b34fb'),
        );
        return cubit.readDescriptor(descriptor);
      },
      verify: (cubit) {
        final key = '00002902-0000-1000-8000-00805f9b34fb';
        expect(cubit.state.descriptorValues[key], isNotNull);
        expect(cubit.state.readingDescriptors, isEmpty);
        expect(cubit.state.failedDescriptors, isEmpty);
      },
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'readDescriptor marks failed on error',
      setUp: () {
        when(() => mockReadDescriptor(any()))
            .thenThrow(Exception('Descriptor error'));
      },
      build: createCubit,
      act: (cubit) {
        final descriptor = MockRemoteDescriptor();
        when(() => descriptor.uuid).thenReturn(
          UUID('00002902-0000-1000-8000-00805f9b34fb'),
        );
        return cubit.readDescriptor(descriptor);
      },
      verify: (cubit) {
        final key = '00002902-0000-1000-8000-00805f9b34fb';
        expect(cubit.state.failedDescriptors, contains(key));
        expect(cubit.state.readingDescriptors, isEmpty);
        expect(cubit.state.error, contains('Descriptor read failed'));
      },
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'clearLog empties the log',
      build: createCubit,
      seed: () => CharacteristicState(
        characteristic: mockCharacteristic,
        log: [LogEntry('Read', Uint8List.fromList([0x01]))],
      ),
      act: (cubit) => cubit.clearLog(),
      expect: () => [
        isA<CharacteristicState>().having((s) => s.log, 'log', isEmpty),
      ],
    );

    blocTest<CharacteristicCubit, CharacteristicState>(
      'clearError clears the error',
      build: createCubit,
      seed: () => CharacteristicState(
        characteristic: mockCharacteristic,
        error: 'Some error',
      ),
      act: (cubit) => cubit.clearError(),
      expect: () => [
        isA<CharacteristicState>().having((s) => s.error, 'error', isNull),
      ],
    );
  });
}

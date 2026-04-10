import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/scanner/application/get_bluetooth_state.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockScannerRepository mockRepository;
  late GetBluetoothState useCase;

  setUp(() {
    mockRepository = MockScannerRepository();
    useCase = GetBluetoothState(mockRepository);
  });

  group('GetBluetoothState', () {
    test('should return current state from repository', () {
      // Arrange
      when(() => mockRepository.currentState).thenReturn(BluetoothState.on);

      // Act
      final result = useCase.current;

      // Assert
      expect(result, BluetoothState.on);
      verify(() => mockRepository.currentState).called(1);
    });

    test('should return state stream from repository', () async {
      // Arrange
      when(() => mockRepository.stateStream).thenAnswer(
        (_) => Stream.fromIterable([BluetoothState.off, BluetoothState.on]),
      );

      // Act
      final result = useCase();
      final states = await result.toList();

      // Assert
      expect(states, [BluetoothState.off, BluetoothState.on]);
      verify(() => mockRepository.stateStream).called(1);
    });
  });
}

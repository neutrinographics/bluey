import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/service_explorer/application/subscribe_to_characteristic.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockCharacteristicRepository mockRepository;
  late SubscribeToCharacteristic useCase;

  setUpAll(() {
    registerFallbackValue(FakeRemoteCharacteristic());
  });

  setUp(() {
    mockRepository = MockCharacteristicRepository();
    useCase = SubscribeToCharacteristic(mockRepository);
  });

  group('SubscribeToCharacteristic', () {
    test('should return stream of values from repository', () async {
      // Arrange
      final mockCharacteristic = MockRemoteCharacteristic();
      final value1 = Uint8List.fromList([0x01]);
      final value2 = Uint8List.fromList([0x02]);

      when(
        () => mockRepository.subscribeToCharacteristic(any()),
      ).thenAnswer((_) => Stream.fromIterable([value1, value2]));

      // Act
      final stream = useCase(mockCharacteristic);
      final values = await stream.toList();

      // Assert
      expect(values, [value1, value2]);
      verify(
        () => mockRepository.subscribeToCharacteristic(mockCharacteristic),
      ).called(1);
    });
  });
}

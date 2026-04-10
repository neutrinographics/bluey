import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/service_explorer/application/read_characteristic.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockCharacteristicRepository mockRepository;
  late ReadCharacteristic useCase;

  setUpAll(() {
    registerFallbackValue(FakeRemoteCharacteristic());
  });

  setUp(() {
    mockRepository = MockCharacteristicRepository();
    useCase = ReadCharacteristic(mockRepository);
  });

  group('ReadCharacteristic', () {
    test(
      'should call repository.readCharacteristic and return value',
      () async {
        // Arrange
        final mockCharacteristic = MockRemoteCharacteristic();
        final expectedValue = Uint8List.fromList([0x01, 0x02, 0x03]);

        when(
          () => mockRepository.readCharacteristic(any()),
        ).thenAnswer((_) async => expectedValue);

        // Act
        final result = await useCase(mockCharacteristic);

        // Assert
        expect(result, expectedValue);
        verify(
          () => mockRepository.readCharacteristic(mockCharacteristic),
        ).called(1);
      },
    );
  });
}

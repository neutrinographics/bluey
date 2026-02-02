import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/gatt/domain/use_cases/write_characteristic.dart';

import '../../../mocks/mock_repositories.dart';
import '../../../mocks/mock_bluey.dart';

void main() {
  late MockGattRepository mockRepository;
  late WriteCharacteristic useCase;

  setUpAll(() {
    registerFallbackValue(FakeRemoteCharacteristic());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockRepository = MockGattRepository();
    useCase = WriteCharacteristic(mockRepository);
  });

  group('WriteCharacteristic', () {
    test('should call repository.writeCharacteristic with response', () async {
      // Arrange
      final mockCharacteristic = MockRemoteCharacteristic();
      final value = Uint8List.fromList([0x01, 0x02, 0x03]);

      when(
        () => mockRepository.writeCharacteristic(
          any(),
          any(),
          withResponse: any(named: 'withResponse'),
        ),
      ).thenAnswer((_) async {});

      // Act
      await useCase(mockCharacteristic, value, withResponse: true);

      // Assert
      verify(
        () => mockRepository.writeCharacteristic(
          mockCharacteristic,
          value,
          withResponse: true,
        ),
      ).called(1);
    });

    test(
      'should call repository.writeCharacteristic without response',
      () async {
        // Arrange
        final mockCharacteristic = MockRemoteCharacteristic();
        final value = Uint8List.fromList([0x01, 0x02, 0x03]);

        when(
          () => mockRepository.writeCharacteristic(
            any(),
            any(),
            withResponse: any(named: 'withResponse'),
          ),
        ).thenAnswer((_) async {});

        // Act
        await useCase(mockCharacteristic, value, withResponse: false);

        // Assert
        verify(
          () => mockRepository.writeCharacteristic(
            mockCharacteristic,
            value,
            withResponse: false,
          ),
        ).called(1);
      },
    );
  });
}

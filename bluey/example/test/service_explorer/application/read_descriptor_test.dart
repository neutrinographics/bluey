import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/service_explorer/application/read_descriptor.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockCharacteristicRepository mockRepository;
  late ReadDescriptor useCase;

  setUpAll(() {
    registerFallbackValue(FakeRemoteDescriptor());
  });

  setUp(() {
    mockRepository = MockCharacteristicRepository();
    useCase = ReadDescriptor(mockRepository);
  });

  group('ReadDescriptor', () {
    test('should call repository.readDescriptor and return value', () async {
      // Arrange
      final mockDescriptor = MockRemoteDescriptor();
      final expectedValue = Uint8List.fromList([0x01, 0x00]);

      when(
        () => mockRepository.readDescriptor(any()),
      ).thenAnswer((_) async => expectedValue);

      // Act
      final result = await useCase(mockDescriptor);

      // Assert
      expect(result, expectedValue);
      verify(() => mockRepository.readDescriptor(mockDescriptor)).called(1);
    });
  });
}

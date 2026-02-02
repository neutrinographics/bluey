import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/server/domain/use_cases/stop_advertising.dart';

import '../../../mocks/mock_repositories.dart';

void main() {
  late MockServerRepository mockRepository;
  late StopAdvertising useCase;

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = StopAdvertising(mockRepository);
  });

  group('StopAdvertising', () {
    test('should call repository.stopAdvertising', () async {
      // Arrange
      when(() => mockRepository.stopAdvertising()).thenAnswer((_) async {});

      // Act
      await useCase();

      // Assert
      verify(() => mockRepository.stopAdvertising()).called(1);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/application/add_service.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late AddService useCase;

  setUpAll(() {
    registerFallbackValue(FakeHostedService());
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = AddService(mockRepository);
  });

  group('AddService', () {
    test('should call repository.addService', () async {
      // Arrange
      final service = HostedService(
        uuid: UUID('12345678-1234-1234-1234-123456789abc'),
        isPrimary: true,
        characteristics: [],
      );

      when(() => mockRepository.addService(any())).thenAnswer((_) async {});

      // Act
      await useCase(service);

      // Assert
      verify(() => mockRepository.addService(service)).called(1);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/connection/application/get_services.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectionRepository mockRepository;
  late GetServices useCase;

  setUpAll(() {
    registerFallbackValue(FakeConnection());
  });

  setUp(() {
    mockRepository = MockConnectionRepository();
    useCase = GetServices(mockRepository);
  });

  group('GetServices', () {
    test('should call repository.getServices and return services', () async {
      // Arrange
      final mockConnection = MockConnection();
      final mockService = MockRemoteService();

      when(
        () => mockRepository.getServices(any()),
      ).thenAnswer((_) async => [mockService]);

      // Act
      final result = await useCase(mockConnection);

      // Assert
      expect(result, [mockService]);
      verify(() => mockRepository.getServices(mockConnection)).called(1);
    });

    test('should return empty list when no services found', () async {
      // Arrange
      final mockConnection = MockConnection();

      when(() => mockRepository.getServices(any())).thenAnswer((_) async => []);

      // Act
      final result = await useCase(mockConnection);

      // Assert
      expect(result, isEmpty);
    });
  });
}

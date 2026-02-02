import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/connection/domain/use_cases/discover_services.dart';

import '../../../mocks/mock_repositories.dart';
import '../../../mocks/mock_bluey.dart';

void main() {
  late MockConnectionRepository mockRepository;
  late DiscoverServices useCase;

  setUpAll(() {
    registerFallbackValue(FakeConnection());
  });

  setUp(() {
    mockRepository = MockConnectionRepository();
    useCase = DiscoverServices(mockRepository);
  });

  group('DiscoverServices', () {
    test(
      'should call repository.discoverServices and return services',
      () async {
        // Arrange
        final mockConnection = MockConnection();
        final mockService = MockRemoteService();

        when(
          () => mockRepository.discoverServices(any()),
        ).thenAnswer((_) async => [mockService]);

        // Act
        final result = await useCase(mockConnection);

        // Assert
        expect(result, [mockService]);
        verify(() => mockRepository.discoverServices(mockConnection)).called(1);
      },
    );

    test('should return empty list when no services found', () async {
      // Arrange
      final mockConnection = MockConnection();

      when(
        () => mockRepository.discoverServices(any()),
      ).thenAnswer((_) async => []);

      // Act
      final result = await useCase(mockConnection);

      // Assert
      expect(result, isEmpty);
    });
  });
}

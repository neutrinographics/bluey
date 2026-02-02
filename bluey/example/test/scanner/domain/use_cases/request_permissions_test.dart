import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/scanner/domain/use_cases/request_permissions.dart';

import '../../../mocks/mock_repositories.dart';

void main() {
  late MockScannerRepository mockRepository;
  late RequestPermissions useCase;

  setUp(() {
    mockRepository = MockScannerRepository();
    useCase = RequestPermissions(mockRepository);
  });

  group('RequestPermissions', () {
    test('should return true when permission is granted', () async {
      // Arrange
      when(() => mockRepository.authorize()).thenAnswer((_) async => true);

      // Act
      final result = await useCase();

      // Assert
      expect(result, true);
      verify(() => mockRepository.authorize()).called(1);
    });

    test('should return false when permission is denied', () async {
      // Arrange
      when(() => mockRepository.authorize()).thenAnswer((_) async => false);

      // Act
      final result = await useCase();

      // Assert
      expect(result, false);
      verify(() => mockRepository.authorize()).called(1);
    });
  });
}

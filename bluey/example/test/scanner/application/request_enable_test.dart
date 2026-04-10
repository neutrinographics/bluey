import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/scanner/application/request_enable.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockScannerRepository mockRepository;
  late RequestEnable useCase;

  setUp(() {
    mockRepository = MockScannerRepository();
    useCase = RequestEnable(mockRepository);
  });

  group('RequestEnable', () {
    test('should call repository.requestEnable', () async {
      // Arrange
      when(() => mockRepository.requestEnable()).thenAnswer((_) async => true);

      // Act
      await useCase();

      // Assert
      verify(() => mockRepository.requestEnable()).called(1);
    });

    test('should call repository.openSettings', () async {
      // Arrange
      when(() => mockRepository.openSettings()).thenAnswer((_) async {});

      // Act
      await useCase.openSettings();

      // Assert
      verify(() => mockRepository.openSettings()).called(1);
    });
  });
}

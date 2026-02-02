import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/scanner/domain/use_cases/stop_scan.dart';

import '../../../mocks/mock_repositories.dart';

void main() {
  late MockScannerRepository mockRepository;
  late StopScan useCase;

  setUp(() {
    mockRepository = MockScannerRepository();
    useCase = StopScan(mockRepository);
  });

  group('StopScan', () {
    test('should call repository.stopScan', () async {
      // Arrange
      when(() => mockRepository.stopScan()).thenAnswer((_) async {});

      // Act
      await useCase();

      // Assert
      verify(() => mockRepository.stopScan()).called(1);
    });
  });
}

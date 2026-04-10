import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/application/start_advertising.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockServerRepository mockRepository;
  late StartAdvertising useCase;

  setUpAll(() {
    registerFallbackValue(<UUID>[]);
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = StartAdvertising(mockRepository);
  });

  group('StartAdvertising', () {
    test('should call repository.startAdvertising with parameters', () async {
      // Arrange
      final serviceUuid = UUID('12345678-1234-1234-1234-123456789abc');

      when(
        () => mockRepository.startAdvertising(
          name: any(named: 'name'),
          services: any(named: 'services'),
          manufacturerData: any(named: 'manufacturerData'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async {});

      // Act
      await useCase(name: 'Test Device', services: [serviceUuid]);

      // Assert
      verify(
        () => mockRepository.startAdvertising(
          name: 'Test Device',
          services: [serviceUuid],
        ),
      ).called(1);
    });
  });
}

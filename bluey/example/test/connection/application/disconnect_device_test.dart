import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/connection/application/disconnect_device.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectionRepository mockRepository;
  late DisconnectDevice useCase;

  setUpAll(() {
    registerFallbackValue(FakeConnection());
  });

  setUp(() {
    mockRepository = MockConnectionRepository();
    useCase = DisconnectDevice(mockRepository);
  });

  group('DisconnectDevice', () {
    test('should call repository.disconnect', () async {
      // Arrange
      final mockConnection = MockConnection();

      when(() => mockRepository.disconnect(any())).thenAnswer((_) async {});

      // Act
      await useCase(mockConnection);

      // Assert
      verify(() => mockRepository.disconnect(mockConnection)).called(1);
    });
  });
}

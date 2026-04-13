import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/connection/application/connect_to_device.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockConnectionRepository mockRepository;
  late ConnectToDevice useCase;

  setUpAll(() {
    registerFallbackValue(FakeDevice());
  });

  setUp(() {
    mockRepository = MockConnectionRepository();
    useCase = ConnectToDevice(mockRepository);
  });

  group('ConnectToDevice', () {
    test('should call repository.connect and return connection', () async {
      // Arrange
      final mockDevice = Device(
        id: UUID('00000000-0000-0000-0000-000000000001'),
        address: '00:11:22:33:44:55',
        name: 'Test Device',
      );
      final mockConnection = MockConnection();

      when(
        () => mockRepository.connect(any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => mockConnection);

      // Act
      final result = await useCase(mockDevice);

      // Assert
      expect(result, mockConnection);
      verify(() => mockRepository.connect(mockDevice, timeout: null)).called(1);
    });

    test('should pass timeout to repository', () async {
      // Arrange
      final mockDevice = Device(
        id: UUID('00000000-0000-0000-0000-000000000001'),
        address: '00:11:22:33:44:55',
        name: 'Test Device',
      );
      final mockConnection = MockConnection();
      const timeout = Duration(seconds: 30);

      when(
        () => mockRepository.connect(any(), timeout: any(named: 'timeout')),
      ).thenAnswer((_) async => mockConnection);

      // Act
      await useCase(mockDevice, timeout: timeout);

      // Assert
      verify(
        () => mockRepository.connect(mockDevice, timeout: timeout),
      ).called(1);
    });
  });
}

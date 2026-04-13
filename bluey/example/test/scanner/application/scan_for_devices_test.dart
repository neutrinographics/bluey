import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/scanner/application/scan_for_devices.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockScannerRepository mockRepository;
  late ScanForDevices useCase;

  setUp(() {
    mockRepository = MockScannerRepository();
    useCase = ScanForDevices(mockRepository);
  });

  group('ScanForDevices', () {
    test('should call repository.scan and return scan result stream', () async {
      // Arrange
      final mockResult = ScanResult(
        device: Device(
          id: UUID('00000000-0000-0000-0000-000000000001'),
          address: '00:11:22:33:44:55',
          name: 'Test Device',
        ),
        rssi: -50,
        advertisement: Advertisement.empty(),
        lastSeen: DateTime.now(),
      );

      when(
        () => mockRepository.scan(timeout: any(named: 'timeout')),
      ).thenAnswer((_) => Stream.value(mockResult));

      // Act
      final result = useCase(timeout: const Duration(seconds: 10));
      final results = await result.toList();

      // Assert
      expect(results, [mockResult]);
      verify(
        () => mockRepository.scan(timeout: const Duration(seconds: 10)),
      ).called(1);
    });

    test('should scan without timeout when not specified', () async {
      // Arrange
      when(
        () => mockRepository.scan(timeout: any(named: 'timeout')),
      ).thenAnswer((_) => const Stream.empty());

      // Act
      final result = useCase();
      await result.toList();

      // Assert
      verify(() => mockRepository.scan(timeout: null)).called(1);
    });
  });
}

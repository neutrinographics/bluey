import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/application/send_notification.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late SendNotification useCase;

  setUpAll(() {
    registerFallbackValue(FakeUUID());
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = SendNotification(mockRepository);
  });

  group('SendNotification', () {
    test('should call repository.notify with uuid and data', () async {
      // Arrange
      final charUuid = UUID('12345678-1234-1234-1234-123456789abd');
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);

      when(() => mockRepository.notify(any(), any())).thenAnswer((_) async {});

      // Act
      await useCase(charUuid, data);

      // Assert
      verify(() => mockRepository.notify(charUuid, data)).called(1);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/application/reset_server.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late ResetServer useCase;

  final testId = ServerId('12345678-1234-4234-8234-123456789abc');

  setUpAll(() {
    registerFallbackValue(testId);
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = ResetServer(mockRepository);
  });

  group('ResetServer', () {
    test('should call repository.resetServer and return server', () async {
      final mockServer = MockServer();
      when(
        () => mockRepository.resetServer(identity: any(named: 'identity')),
      ).thenAnswer((_) async => mockServer);

      final result = await useCase(identity: testId);

      expect(result, mockServer);
      verify(() => mockRepository.resetServer(identity: testId)).called(1);
    });

    test('should return null when platform does not support server', () async {
      when(
        () => mockRepository.resetServer(identity: any(named: 'identity')),
      ).thenAnswer((_) async => null);

      final result = await useCase(identity: testId);

      expect(result, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

import 'package:bluey_example/features/server/application/set_server_identity.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockServerRepository mockRepository;
  late SetServerIdentity useCase;

  final testId = ServerId('12345678-1234-4234-8234-123456789abc');

  setUpAll(() {
    registerFallbackValue(testId);
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = SetServerIdentity(mockRepository);
  });

  group('SetServerIdentity', () {
    test('should call repository.setIdentity', () {
      when(() => mockRepository.setIdentity(any())).thenReturn(null);

      useCase(testId);

      verify(() => mockRepository.setIdentity(testId)).called(1);
    });
  });
}

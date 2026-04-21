import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/server/application/check_server_support.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late CheckServerSupport useCase;

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = CheckServerSupport(mockRepository);
  });

  group('CheckServerSupport', () {
    test('should return true when server is supported', () {
      when(() => mockRepository.getServer()).thenReturn(MockServer());

      expect(useCase(), isTrue);
      verify(() => mockRepository.getServer()).called(1);
    });

    test('should return false when server is not supported', () {
      when(() => mockRepository.getServer()).thenReturn(null);

      expect(useCase(), isFalse);
      verify(() => mockRepository.getServer()).called(1);
    });
  });
}

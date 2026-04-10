import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/server/application/dispose_server.dart';

import '../../mocks/mock_repositories.dart';

void main() {
  late MockServerRepository mockRepository;
  late DisposeServer useCase;

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = DisposeServer(mockRepository);
  });

  group('DisposeServer', () {
    test('should call repository.dispose', () async {
      when(() => mockRepository.dispose()).thenAnswer((_) async {});

      await useCase();

      verify(() => mockRepository.dispose()).called(1);
    });
  });
}

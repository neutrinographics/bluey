import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/server/application/observe_connections.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late ObserveConnections useCase;

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = ObserveConnections(mockRepository);
  });

  group('ObserveConnections', () {
    test('should return connections stream from repository', () {
      final central = MockClient();
      when(
        () => mockRepository.connections,
      ).thenAnswer((_) => Stream.value(central));

      expectLater(useCase(), emits(central));
      verify(() => mockRepository.connections).called(1);
    });

    test('should return empty stream when no connections', () {
      when(
        () => mockRepository.connections,
      ).thenAnswer((_) => const Stream.empty());

      expectLater(useCase(), emitsDone);
    });
  });
}

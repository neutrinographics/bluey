import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/server/application/disconnect_client.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late DisconnectClient useCase;

  setUpAll(() {
    registerFallbackValue(MockClient());
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = DisconnectClient(mockRepository);
  });

  group('DisconnectClient', () {
    test('should call repository.disconnectClient', () async {
      final central = MockClient();
      when(
        () => mockRepository.disconnectClient(any()),
      ).thenAnswer((_) async {});

      await useCase(central);

      verify(() => mockRepository.disconnectClient(central)).called(1);
    });
  });
}

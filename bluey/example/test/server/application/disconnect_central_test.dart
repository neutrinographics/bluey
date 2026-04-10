import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/server/application/disconnect_central.dart';

import '../../mocks/mock_repositories.dart';
import '../../mocks/mock_bluey.dart';

void main() {
  late MockServerRepository mockRepository;
  late DisconnectCentral useCase;

  setUpAll(() {
    registerFallbackValue(MockCentral());
  });

  setUp(() {
    mockRepository = MockServerRepository();
    useCase = DisconnectCentral(mockRepository);
  });

  group('DisconnectCentral', () {
    test('should call repository.disconnectCentral', () async {
      final central = MockCentral();
      when(() => mockRepository.disconnectCentral(any()))
          .thenAnswer((_) async {});

      await useCase(central);

      verify(() => mockRepository.disconnectCentral(central)).called(1);
    });
  });
}

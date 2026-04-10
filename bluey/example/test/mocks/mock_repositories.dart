import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/features/scanner/domain/scanner_repository.dart';
import 'package:bluey_example/features/connection/domain/connection_repository.dart';
import 'package:bluey_example/features/service_explorer/domain/characteristic_repository.dart';
import 'package:bluey_example/features/server/domain/server_repository.dart';

class MockScannerRepository extends Mock implements ScannerRepository {}

class MockConnectionRepository extends Mock implements ConnectionRepository {}

class MockCharacteristicRepository extends Mock
    implements CharacteristicRepository {}

class MockServerRepository extends Mock implements ServerRepository {}

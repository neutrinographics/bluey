import 'package:mocktail/mocktail.dart';

import 'package:bluey_example/scanner/domain/scanner_repository.dart';
import 'package:bluey_example/connection/domain/connection_repository.dart';
import 'package:bluey_example/gatt/domain/gatt_repository.dart';
import 'package:bluey_example/server/domain/server_repository.dart';

class MockScannerRepository extends Mock implements ScannerRepository {}

class MockConnectionRepository extends Mock implements ConnectionRepository {}

class MockGattRepository extends Mock implements GattRepository {}

class MockServerRepository extends Mock implements ServerRepository {}

import 'package:mocktail/mocktail.dart';
import 'package:bluey/bluey.dart';

class MockBluey extends Mock implements Bluey {}

class MockConnection extends Mock implements Connection {}

class MockRemoteService extends Mock implements RemoteService {}

class MockRemoteCharacteristic extends Mock implements RemoteCharacteristic {}

class MockRemoteDescriptor extends Mock implements RemoteDescriptor {}

class MockServer extends Mock implements Server {}

class MockClient extends Mock implements Client {}

/// Fake classes for registerFallbackValue
class FakeDevice extends Fake implements Device {}

class FakeConnection extends Fake implements Connection {}

class FakeRemoteCharacteristic extends Fake implements RemoteCharacteristic {}

class FakeRemoteDescriptor extends Fake implements RemoteDescriptor {}

class FakeHostedService extends Fake implements HostedService {}

class FakeUUID extends Fake implements UUID {}

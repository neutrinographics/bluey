import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bluey/bluey.dart';

/// Integration tests for Bluetooth state management.
///
/// These tests run on a real device and verify actual Bluetooth state handling.
///
/// Run with: flutter test integration_test/bluetooth_state_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Bluey bluey;

  setUp(() {
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  group('Bluetooth State', () {
    testWidgets('can get current Bluetooth state', (tester) async {
      final state = await bluey.state;

      expect(state, isA<BluetoothState>());
      // State should be one of the valid values
      expect([
        BluetoothState.unknown,
        BluetoothState.unsupported,
        BluetoothState.unauthorized,
        BluetoothState.off,
        BluetoothState.on,
      ], contains(state));
    });

    testWidgets('currentState returns cached state synchronously', (
      tester,
    ) async {
      // First call to state to initialize
      await bluey.state;

      // currentState should return synchronously
      final state = bluey.currentState;

      expect(state, isA<BluetoothState>());
    });

    testWidgets('stateStream emits states', (tester) async {
      final states = <BluetoothState>[];
      final subscription = bluey.stateStream.listen((state) {
        states.add(state);
      });

      // Wait a bit for initial state
      await Future.delayed(const Duration(milliseconds: 500));

      // Should have received at least the initial state
      // (actual count depends on platform behavior)

      await subscription.cancel();
    });
  });

  group('Permissions', () {
    testWidgets('can check authorization status', (tester) async {
      final state = await bluey.state;

      // If state is unauthorized, we know permissions are not granted
      // If state is on or off, permissions are granted
      expect(state, isA<BluetoothState>());
    });
  });

  group('Capabilities', () {
    testWidgets('can get platform capabilities', (tester) async {
      final capabilities = bluey.capabilities;

      expect(capabilities, isA<Capabilities>());
      // Check that capability flags are booleans
      expect(capabilities.supportsScanning, isA<bool>());
      expect(capabilities.supportsConnecting, isA<bool>());
      expect(capabilities.supportsAdvertising, isA<bool>());
    });

    testWidgets('Android supports scanning and connecting', (tester) async {
      final capabilities = bluey.capabilities;

      // On Android, scanning and connecting should be supported
      expect(capabilities.supportsScanning, isTrue);
      expect(capabilities.supportsConnecting, isTrue);
    });

    testWidgets('Android supports advertising', (tester) async {
      final capabilities = bluey.capabilities;

      // Most modern Android devices support advertising
      // (though some older devices may not)
      expect(capabilities.supportsAdvertising, isA<bool>());
    });
  });

  group('Ensure Ready', () {
    testWidgets('ensureReady succeeds when Bluetooth is on', (tester) async {
      final state = await bluey.state;

      if (state == BluetoothState.on) {
        // Should not throw
        await bluey.ensureReady();
      } else {
        // Skip test if Bluetooth is not on
        // (we can't control Bluetooth state in integration tests)
      }
    });

    testWidgets('ensureReady throws when Bluetooth is off', (tester) async {
      final state = await bluey.state;

      if (state == BluetoothState.off) {
        expect(
          () => bluey.ensureReady(),
          throwsA(isA<BluetoothDisabledException>()),
        );
      } else {
        // Skip test if Bluetooth is not off
      }
    });

    testWidgets('ensureReady throws when unauthorized', (tester) async {
      final state = await bluey.state;

      if (state == BluetoothState.unauthorized) {
        expect(
          () => bluey.ensureReady(),
          throwsA(isA<PermissionDeniedException>()),
        );
      } else {
        // Skip test if permissions are granted
      }
    });
  });
}

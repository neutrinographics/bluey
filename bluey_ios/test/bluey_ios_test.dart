import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_ios/bluey_ios.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlueyIos', () {
    late BlueyIos bluey;

    setUp(() {
      bluey = BlueyIos();
    });

    test('registers as platform instance', () {
      BlueyIos.registerWith();
      expect(BlueyPlatform.instance, isA<BlueyIos>());
    });

    test('has iOS capabilities', () {
      expect(bluey.capabilities, equals(Capabilities.iOS));
    });

    group('iOS-unsupported features', () {
      test('requestEnable throws UnsupportedError', () {
        expect(() => bluey.requestEnable(), throwsA(isA<UnsupportedError>()));
      });

      test('requestMtu throws UnsupportedError', () {
        expect(
          () => bluey.requestMtu('device-id', 512),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('removeBond throws UnsupportedError', () {
        expect(
          () => bluey.removeBond('device-id'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getPhy throws UnsupportedError', () {
        expect(
          () => bluey.getPhy('device-id'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestPhy throws UnsupportedError', () {
        expect(
          () => bluey.requestPhy('device-id', PlatformPhy.le2m, null),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('getConnectionParameters throws UnsupportedError', () {
        expect(
          () => bluey.getConnectionParameters('device-id'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('requestConnectionParameters throws UnsupportedError', () {
        expect(
          () => bluey.requestConnectionParameters(
            'device-id',
            const PlatformConnectionParameters(
              intervalMs: 15,
              latency: 0,
              timeoutMs: 5000,
            ),
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('iOS bonding behavior', () {
      test(
        'getBondState returns none (iOS handles bonding automatically)',
        () async {
          final state = await bluey.getBondState('device-id');
          expect(state, equals(PlatformBondState.none));
        },
      );

      test('bondStateStream returns empty stream', () {
        final stream = bluey.bondStateStream('device-id');
        expect(stream, emitsDone);
      });

      test('bond completes without error (no-op on iOS)', () async {
        // Should complete without throwing
        await bluey.bond('device-id');
      });

      test('getBondedDevices returns empty list', () async {
        final devices = await bluey.getBondedDevices();
        expect(devices, isEmpty);
      });
    });

    group('iOS PHY behavior', () {
      test('phyStream returns empty stream', () {
        final stream = bluey.phyStream('device-id');
        expect(stream, emitsDone);
      });
    });
  });
}

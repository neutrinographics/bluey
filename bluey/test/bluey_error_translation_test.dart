import 'dart:async';

import 'package:bluey/bluey.dart';
import 'package:bluey_platform_interface/bluey_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_platform.dart';

/// Tests pinning down the I099 contract on the `Bluey` facade: every
/// `_wrapError` call site, when handed a typed platform-interface
/// exception, must surface a typed `BlueyException`. Pre-I099 the code
/// matched on `error.toString().toLowerCase()` substrings — typed
/// exceptions whose `toString()` didn't include the right keyword (or
/// contained misleading ones) were silently misclassified.
void main() {
  late _ErroringFakePlatform mockPlatform;
  late Bluey bluey;

  setUp(() {
    mockPlatform = _ErroringFakePlatform();
    platform.BlueyPlatform.instance = mockPlatform;
    bluey = Bluey();
  });

  tearDown(() async {
    await bluey.dispose();
  });

  group('Bluey error translation (I099)', () {
    test('configure() — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.configureError =
          const platform.PlatformPermissionDeniedException(
        'configure',
        permission: 'BLUETOOTH_CONNECT',
      );
      await expectLater(
        bluey.configure(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('state getter — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.getStateError =
          const platform.GattOperationUnknownPlatformException(
        'getState',
        code: 'unexpected-state',
      );
      await expectLater(
        bluey.state,
        throwsA(isA<BlueyPlatformException>()),
      );
    });

    test('requestEnable() — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.requestEnableError =
          const platform.PlatformPermissionDeniedException(
        'requestEnable',
        permission: 'BLUETOOTH',
      );
      await expectLater(
        bluey.requestEnable(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('authorize() — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.authorizeError =
          const platform.GattOperationUnknownPlatformException(
        'authorize',
        code: 'something-failed',
      );
      await expectLater(
        bluey.authorize(),
        throwsA(isA<BlueyPlatformException>()),
      );
    });

    test('openSettings() — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.openSettingsError =
          const platform.GattOperationUnknownPlatformException(
        'openSettings',
        code: 'unavailable',
      );
      await expectLater(
        bluey.openSettings(),
        throwsA(isA<BlueyPlatformException>()),
      );
    });

    test(
        'connect() — typed platform timeout → typed BlueyException '
        '(no string-matched ConnectionException)', () async {
      mockPlatform.connectError =
          const platform.GattOperationTimeoutException('connect');
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddee01'),
      );
      await expectLater(
        bluey.connect(device),
        throwsA(isA<BlueyException>()),
      );
    });

    test('bondedDevices — typed platform exception → typed BlueyException',
        () async {
      mockPlatform.bondedDevicesError =
          const platform.PlatformPermissionDeniedException(
        'getBondedDevices',
        permission: 'BLUETOOTH_CONNECT',
      );
      await expectLater(
        bluey.bondedDevices,
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test(
        'state-stream onError translates platform errors to BlueyException '
        'and re-emits on the stream\'s error channel', () async {
      // Capture the next error emission on bluey.stateStream.
      final errorCompleter = Completer<Object>();
      bluey.stateStream.listen(
        (_) {},
        onError: (Object e) {
          if (!errorCompleter.isCompleted) errorCompleter.complete(e);
        },
      );

      // Push a typed exception through the platform's state stream.
      mockPlatform.injectStateStreamError(
        const platform.PlatformPermissionDeniedException(
          'stateStream',
          permission: 'BLUETOOTH',
        ),
      );

      final received = await errorCompleter.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('No error received on stateStream'),
      );
      expect(received, isA<PermissionDeniedException>());
    });
  });
}

/// Extends [FakeBlueyPlatform] (which already stubs every abstract
/// method) with per-method error injection for the 7 non-GATT methods
/// the I099 commit-2 migration touches, plus a state-stream error
/// injector for the onError-handler test.
base class _ErroringFakePlatform extends FakeBlueyPlatform {
  Object? configureError;
  Object? getStateError;
  Object? requestEnableError;
  Object? authorizeError;
  Object? openSettingsError;
  Object? connectError;
  Object? bondedDevicesError;

  @override
  Future<void> configure(platform.BlueyConfig config) async {
    if (configureError != null) throw configureError!;
    return super.configure(config);
  }

  @override
  Future<platform.BluetoothState> getState() async {
    if (getStateError != null) throw getStateError!;
    return super.getState();
  }

  @override
  Future<bool> requestEnable() async {
    if (requestEnableError != null) throw requestEnableError!;
    return super.requestEnable();
  }

  @override
  Future<bool> authorize() async {
    if (authorizeError != null) throw authorizeError!;
    return super.authorize();
  }

  @override
  Future<void> openSettings() async {
    if (openSettingsError != null) throw openSettingsError!;
    return super.openSettings();
  }

  @override
  Future<String> connect(
    String deviceId,
    platform.PlatformConnectConfig config,
  ) async {
    if (connectError != null) throw connectError!;
    return super.connect(deviceId, config);
  }

  @override
  Future<List<platform.PlatformDevice>> getBondedDevices() async {
    if (bondedDevicesError != null) throw bondedDevicesError!;
    return super.getBondedDevices();
  }

  /// Local stream replaces `FakeBlueyPlatform`'s state stream so the
  /// test can push errors onto it. `Bluey()` subscribes to whatever
  /// `stateStream` returns at construction time.
  final _stateController =
      StreamController<platform.BluetoothState>.broadcast();

  @override
  Stream<platform.BluetoothState> get stateStream => _stateController.stream;

  /// Pushes [error] onto the platform's state stream so the `Bluey`
  /// listener's `onError` translation can be exercised.
  void injectStateStreamError(Object error) {
    _stateController.addError(error);
  }
}

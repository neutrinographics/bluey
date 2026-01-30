import 'dart:async';
import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanMode', () {
    test('has all expected values', () {
      expect(ScanMode.values, hasLength(3));
      expect(ScanMode.values, contains(ScanMode.balanced));
      expect(ScanMode.values, contains(ScanMode.lowLatency));
      expect(ScanMode.values, contains(ScanMode.lowPower));
    });
  });

  group('ScanStream', () {
    late MockScanStream scanStream;

    setUp(() {
      scanStream = MockScanStream();
    });

    tearDown(() {
      scanStream.dispose();
    });

    test('is a Stream of Device', () {
      expect(scanStream, isA<Stream<Device>>());
    });

    test('isScanning returns true when scanning', () {
      expect(scanStream.isScanning, isTrue);
    });

    test('isScanning returns false after stop', () async {
      await scanStream.stop();
      expect(scanStream.isScanning, isFalse);
    });

    test('stop() stops the scan', () async {
      await scanStream.stop();
      // Verify stream completes after stop
      expect(scanStream.isScanning, isFalse);
    });

    test('emits devices when scanning', () async {
      final device = Device(
        id: UUID('00000000-0000-0000-0000-aabbccddeeff'),
        rssi: -60,
        advertisement: Advertisement.empty(),
      );

      final devices = <Device>[];
      final subscription = scanStream.listen(devices.add);

      scanStream.addDevice(device);
      await Future.delayed(Duration(milliseconds: 10));

      expect(devices, hasLength(1));
      expect(devices.first.id, equals(device.id));

      await subscription.cancel();
    });

    test('stream completes when stop is called', () async {
      var completed = false;
      scanStream.listen(
        (_) {},
        onDone: () => completed = true,
      );

      await scanStream.stop();
      await Future.delayed(Duration(milliseconds: 10));

      expect(completed, isTrue);
    });
  });
}

/// Mock implementation for testing ScanStream interface
class MockScanStream extends Stream<Device> implements ScanStream {
  final _controller = StreamController<Device>.broadcast();
  bool _isScanning = true;

  @override
  bool get isScanning => _isScanning;

  @override
  Future<void> stop() async {
    _isScanning = false;
    await _controller.close();
  }

  void addDevice(Device device) {
    if (_isScanning) {
      _controller.add(device);
    }
  }

  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  @override
  StreamSubscription<Device> listen(
    void Function(Device event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

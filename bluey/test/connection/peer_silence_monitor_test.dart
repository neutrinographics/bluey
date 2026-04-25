import 'package:bluey/src/connection/peer_silence_monitor.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerSilenceMonitor', () {
    test('start enables the monitor; stop disables it', () {
      var fired = false;
      final monitor = PeerSilenceMonitor(
        peerSilenceTimeout: const Duration(seconds: 20),
        activityWindow: const Duration(seconds: 5),
        onSilent: () => fired = true,
      );
      expect(monitor.isRunning, isFalse);
      monitor.start();
      expect(monitor.isRunning, isTrue);
      monitor.stop();
      expect(monitor.isRunning, isFalse);
      expect(fired, isFalse);
    });

    test('recordPeerFailure arms the death watch', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        monitor.recordPeerFailure();
        expect(monitor.firstFailureAt, isNotNull);
        expect(monitor.isDeathWatchActive, isTrue);
        monitor.stop();
      });
    });

    test('recordActivity cancels the death watch', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 5));
        monitor.recordActivity();
        expect(monitor.firstFailureAt, isNull);
        expect(monitor.isDeathWatchActive, isFalse);
        async.elapse(const Duration(seconds: 30));
        expect(fired, isFalse);
      });
    });

    test('multiple failures do not reset the deadline', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        monitor.recordPeerFailure();
        final firstAt = monitor.firstFailureAt;
        async.elapse(const Duration(seconds: 10));
        monitor.recordPeerFailure();
        expect(monitor.firstFailureAt, equals(firstAt));
        monitor.stop();
      });
    });

    test('onSilent fires after peerSilenceTimeout from first failure', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 19));
        expect(fired, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(fired, isTrue);
        // Single-fire: monitor is no longer running.
        expect(monitor.isRunning, isFalse);
      });
    });

    test('stop cancels the timer; onSilent does not fire', () {
      fakeAsync((async) {
        var fired = false;
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () => fired = true,
        )..start();
        monitor.recordPeerFailure();
        async.elapse(const Duration(seconds: 5));
        monitor.stop();
        async.elapse(const Duration(seconds: 30));
        expect(fired, isFalse);
      });
    });

    test('failure recorded before start is ignored', () {
      var fired = false;
      final monitor = PeerSilenceMonitor(
        peerSilenceTimeout: const Duration(seconds: 20),
        activityWindow: const Duration(seconds: 5),
        onSilent: () => fired = true,
      );
      monitor.recordPeerFailure();
      expect(monitor.firstFailureAt, isNull);
      expect(fired, isFalse);
    });

    test('timeUntilNextProbe and updateActivityWindow', () {
      fakeAsync((async) {
        final monitor = PeerSilenceMonitor(
          peerSilenceTimeout: const Duration(seconds: 20),
          activityWindow: const Duration(seconds: 5),
          onSilent: () {},
        )..start();
        // No activity yet → returns activityWindow.
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 5)));
        monitor.recordActivity();
        async.elapse(const Duration(seconds: 2));
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 3)));
        monitor.updateActivityWindow(const Duration(seconds: 10));
        expect(monitor.timeUntilNextProbe(),
            equals(const Duration(seconds: 8)));
        monitor.stop();
      });
    });
  });
}

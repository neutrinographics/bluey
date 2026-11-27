import 'dart:async';

import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../domain/radio_outage.dart';

/// The platform's adapter state as outages: every state that is not `on`,
/// and `unknown` for an error on the state stream.
///
/// An error is an outage because a context that cannot tell whether the
/// radio is usable must not carry on as if it were.
Stream<RadioOutage> radioOutagesOf(BlueyPlatform platform) =>
    platform.stateStream.transform(
      StreamTransformer.fromHandlers(
        handleData: (state, sink) {
          final outage = _outageOf(state);
          if (outage != null) sink.add(outage);
        },
        handleError: (_, _, sink) => sink.add(RadioOutage.unknown),
      ),
    );

RadioOutage? _outageOf(BluetoothState state) => switch (state) {
  BluetoothState.on => null,
  BluetoothState.off => RadioOutage.off,
  BluetoothState.unauthorized => RadioOutage.unauthorized,
  BluetoothState.unsupported => RadioOutage.unsupported,
  BluetoothState.unknown => RadioOutage.unknown,
};

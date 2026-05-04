import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

import 'features/server/infrastructure/server_identity_storage.dart';
import 'shared/di/service_locator.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up error logging to console
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    developer.log(
      'Flutter Error: ${details.exceptionAsString()}',
      error: details.exception,
      stackTrace: details.stack,
      name: 'BlueyExample',
    );
  };

  // Handle errors not caught by Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'Unhandled Error: $error',
      error: error,
      stackTrace: stack,
      name: 'BlueyExample',
    );
    return true;
  };

  // Load the persisted server identity before constructing Bluey so
  // that both the central-side peer-protocol upgrade path and the
  // local server can share a single identity-bound instance.
  final localIdentity = await ServerIdentityStorage().loadOrGenerate();

  // Initialize dependency injection
  await setupServiceLocator(localIdentity: localIdentity);

  // Set up Bluey event logging. Errors no longer have a dedicated stream;
  // they surface as typed BlueyException at the call sites that throw them
  // and as warn/error entries on bluey.logEvents (see below).
  final bluey = getIt<Bluey>();
  debugPrint('[Bluey] Subscribing to event stream');
  bluey.events.listen((event) {
    debugPrint('[Bluey] $event');
  });

  // Subscribe to the unified log stream at the most granular level.
  // Covers domain layer + Android + iOS native events in arrival order.
  bluey.setLogLevel(BlueyLogLevel.trace);
  bluey.logEvents.listen((e) {
    final ts = e.timestamp.toIso8601String().substring(11, 23); // HH:mm:ss.SSS
    final level = e.level.name.toUpperCase().padRight(5);
    final data = e.data.isEmpty ? '' : ' ${e.data}';
    final err = e.errorCode == null ? '' : ' err=${e.errorCode}';
    debugPrint('$ts [$level] ${e.context}: ${e.message}$data$err');
  });

  runApp(const BlueyExampleApp());
}

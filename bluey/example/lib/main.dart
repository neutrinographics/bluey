import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

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

  // Initialize dependency injection
  await setupServiceLocator();

  // Set up Bluey error and event logging
  final bluey = getIt<Bluey>();
  bluey.errorStream.listen((error) {
    debugPrint('[Bluey Error] ${error.message}');
  });
  debugPrint('[Bluey] Subscribing to event stream');
  bluey.events.listen((event) {
    debugPrint('[Bluey] $event');
  });

  runApp(const BlueyExampleApp());
}

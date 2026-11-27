import 'package:bluey_platform_interface/bluey_platform_interface.dart';
import 'package:flutter/services.dart' show PlatformException;

/// What any platform call can throw that belongs to no single context.
///
/// Each context words these in its own failures, so the one classification
/// of platform exceptions lives here and a context only chooses its words.
sealed class PlatformError {
  const PlatformError();
}

/// The app lacks a permission the call needs.
final class PermissionDenied extends PlatformError {
  const PermissionDenied(this.permission);

  /// The platform's name for the permission, as the platform reported it.
  final String permission;
}

/// The adapter cannot be used at all right now.
final class RadioUnavailable extends PlatformError {
  const RadioUnavailable();
}

/// Anything the platform should not have thrown, kept so it can be reported.
final class Unexpected extends PlatformError {
  const Unexpected(this.detail, {this.code, required this.cause});

  /// What the platform said went wrong.
  final String detail;

  /// The platform's error code, when it gave one.
  final String? code;

  /// What was thrown.
  final Object cause;
}

/// Classifies what a platform call threw, answering for every throwable so a
/// caller never has to guard its own translation.
PlatformError platformErrorOf(Object error) => switch (error) {
  PlatformPermissionDeniedException(:final permission) => PermissionDenied(
    permission,
  ),
  PlatformBluetoothUnavailableException() => const RadioUnavailable(),
  PlatformException(:final code, :final message) => Unexpected(
    message ?? 'platform error ($code)',
    code: code,
    cause: error,
  ),
  _ => Unexpected(error.toString(), cause: error),
};

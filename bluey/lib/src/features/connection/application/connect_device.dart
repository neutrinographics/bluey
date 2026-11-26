import '../../../shared/domain/device_address.dart';
import '../../../shared/domain/either.dart';
import '../domain/connection_failure.dart';
import 'link_registry.dart';
import 'link_session.dart';

/// What the app's connect asks for: a device by its address, so Connection
/// never names Discovery's device, and the caller's budget.
final class ConnectDeviceRequest {
  const ConnectDeviceRequest({required this.device, this.timeout});

  /// The device to connect to.
  final DeviceAddress device;

  /// The caller's whole budget, waiting included; null leaves the bound to
  /// the platform.
  final Duration? timeout;
}

/// The app's connect: the device's link, new or existing, held by the app
/// until it lets it go, so two connects at once never start two platform
/// connects and a link a borrower opened becomes the app's.
final class ConnectDevice {
  const ConnectDevice(this._registry);

  final LinkRegistry _registry;

  /// Answers the session of the device's link.
  Future<Either<ConnectionFailure, LinkSession>> run(
    ConnectDeviceRequest request,
  ) => _registry.hold(request.device, timeout: request.timeout);
}

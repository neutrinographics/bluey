import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/domain/either.dart';
import '../../application/ports/mtu_negotiation.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/link_operation.dart';
import '../../domain/value_objects/mtu.dart';
import '../../domain/value_objects/write_payload_limit.dart';
import 'platform_failures.dart';

/// Connection's [MtuNegotiation] over [BlueyPlatform].
///
/// What the platform answers is taken as it is: the platform is
/// authoritative about what it negotiated, and a payload limit is only
/// held to the specification's cap on an attribute value.
final class PlatformMtuNegotiation implements MtuNegotiation {
  const PlatformMtuNegotiation(BlueyPlatform platform) : _platform = platform;

  final BlueyPlatform _platform;

  @override
  Future<Either<ConnectionFailure, Mtu>> request(
    LinkId link,
    Mtu desired,
  ) async => (await answering(
    LinkOperation.negotiateMtu,
    () => _platform.requestMtu(link.value, desired.value),
  )).map(Mtu.fromPlatform);

  @override
  Future<Either<ConnectionFailure, WritePayloadLimit>> writePayloadLimit(
    LinkId link, {
    required bool withResponse,
  }) async => (await answering(
    LinkOperation.readWritePayloadLimit,
    () =>
        _platform.getMaximumWriteLength(link.value, withResponse: withResponse),
  )).map(WritePayloadLimit.fromPlatform);
}

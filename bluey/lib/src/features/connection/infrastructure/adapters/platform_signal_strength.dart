import 'package:bluey_platform_interface/bluey_platform_interface.dart';

import '../../../../shared/domain/either.dart';
import '../../application/ports/signal_strength.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_id.dart';
import '../../domain/link_operation.dart';
import 'platform_failures.dart';

/// Connection's [SignalStrength] over [BlueyPlatform].
final class PlatformSignalStrength implements SignalStrength {
  const PlatformSignalStrength(BlueyPlatform platform) : _platform = platform;

  final BlueyPlatform _platform;

  @override
  Future<Either<ConnectionFailure, int>> read(LinkId link) => answering(
    LinkOperation.readSignalStrength,
    () => _platform.readRssi(link.value),
  );
}

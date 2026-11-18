import '../../../../shared/domain/device_address.dart';
import '../../../../shared/domain/either.dart';
import '../../domain/connection_failure.dart';
import '../../domain/link_end.dart';
import '../../domain/link_id.dart';
import '../../domain/link_input.dart';

/// The one way Connection's application layer reaches the radio's links, so
/// a session and the registry can be run over a double and over the platform
/// alike, and never learn the platform's words.
abstract interface class Links {
  /// Opens a link. [timeout] bounds the attempt; null leaves the bound to the platform.
  ///
  /// A device that already has a link answers that link's id, so a second
  /// open never replaces the reports a listener is already reading.
  Future<Either<ConnectionFailure, LinkId>> open(
    DeviceAddress device, {
    Duration? timeout,
  });

  /// Closes [link]. Once it answers success the link's reports end; a failure
  /// leaves the link, and its reports, as they were.
  Future<Either<ConnectionFailure, void>> close(LinkId link);

  /// The radio's reports about one link, for one listener. Reports that arrive before the
  /// listener does are kept. Carries no errors, and ends when the platform has no more to say.
  Stream<LinkReport> reportsOf(LinkId link);

  /// Each time the adapter leaves `on`, for any number of listeners.
  Stream<RadioOutage> get outages;
}

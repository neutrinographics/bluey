import '../../features/connection/application/bonding_session.dart';
import '../../features/connection/application/link_session.dart';
import '../../features/connection/application/mtu_session.dart';
import '../../features/connection/application/parameter_session.dart';
import '../../features/connection/application/phy_session.dart';
import '../../features/connection/domain/connection_failure.dart';
import '../../features/connection/domain/link_end.dart';
import '../../shared/domain/either.dart';
import '../../shared/exceptions.dart';
import 'android_connection_extensions.dart';
import 'connection.dart' show BondState, ConnectionParameters, Mtu, Phy;
import 'connection_failure_translation.dart';

/// One link's bond, PHY, timing and MTU as the Android extension an app reads.
///
/// Each member answers what its session holds, so the extension keeps no
/// copy of any of it and the link's end reaches every member at once.
final class AndroidConnection implements AndroidConnectionExtensions {
  AndroidConnection({
    required LinkSession session,
    required BondingSession bonding,
    required PhySession phy,
    required ParameterSession parameters,
    required MtuSession mtu,
    required String platform,
  }) : _session = session,
       _bonding = bonding,
       _phy = phy,
       _parameters = parameters,
       _mtu = mtu,
       _platform = platform;

  final LinkSession _session;
  final BondingSession _bonding;
  final PhySession _phy;
  final ParameterSession _parameters;
  final MtuSession _mtu;
  final String _platform;

  @override
  BondState get bondState => _valueOf(_bonding.state);

  @override
  Stream<BondState> get bondStateChanges => _changesOf(() => _bonding.changes);

  @override
  Future<void> bond() async => _valueOf(await _bonding.bond());

  @override
  Future<void> removeBond() async => _valueOf(await _bonding.removeBond());

  @override
  Phy get txPhy => _valueOf(_phy.tx);

  @override
  Phy get rxPhy => _valueOf(_phy.rx);

  @override
  Stream<({Phy tx, Phy rx})> get phyChanges => _changesOf(() => _phy.changes);

  @override
  Future<void> requestPhy({Phy? txPhy, Phy? rxPhy}) async =>
      _valueOf(await _phy.request(tx: txPhy, rx: rxPhy));

  @override
  ConnectionParameters get connectionParameters =>
      _valueOf(_parameters.parameters);

  @override
  Future<void> requestConnectionParameters(ConnectionParameters params) async =>
      _valueOf(await _parameters.request(params));

  @override
  Mtu get mtu => _valueOf(_mtu.mtu);

  @override
  Future<Mtu> requestMtu(Mtu desired) async =>
      _valueOf(await _mtu.request(desired));

  T _valueOf<T>(Either<ConnectionFailure, T> answer) =>
      valueOrThrow(answer, device: _session.link.device, platform: _platform);

  /// A session's changes as an app has always followed them: a missing
  /// feature throws at once, and a radio outage reaches each listener as
  /// [StaleHandleException] before the end, since the connection is stale
  /// rather than closed.
  Stream<T> _changesOf<T>(Either<ConnectionFailure, Stream<T>> Function() of) {
    if (of() case Left(value: final FeatureUnsupported missing)) {
      throw _exceptionOf(missing);
    }
    return Stream<T>.multi((listener) {
      of().fold(
        (failure) {
          listener.addError(_exceptionOf(failure));
          listener.closeSync();
        },
        (changes) {
          final followed = changes.listen(
            listener.add,
            onDone: () {
              if (_session.link.end case final EndedByRadioOutage outage) {
                listener.addError(_exceptionOf(LinkHadEnded(outage)));
              }
              listener.closeSync();
            },
          );
          listener.onCancel = followed.cancel;
        },
      );
    }, isBroadcast: true);
  }

  BlueyException _exceptionOf(ConnectionFailure failure) =>
      connectionFailureAsException(
        failure,
        device: _session.link.device,
        platform: _platform,
      );
}

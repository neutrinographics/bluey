import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/connection_settings.dart';

/// Session-scoped store for [ConnectionSettings] the user can tweak before
/// connecting. Not persisted across app restarts — intended for demo use.
class ConnectionSettingsCubit extends Cubit<ConnectionSettings> {
  ConnectionSettingsCubit() : super(const ConnectionSettings());

  void setPeerSilenceTimeout(Duration value) {
    emit(state.copyWith(peerSilenceTimeout: value));
  }
}

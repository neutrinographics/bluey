/// The words an app can read in Connection's log lines and exception
/// messages, in one place.
///
/// They are the words these had before the lifecycle had words of its own,
/// kept so an app's log filters and error handling hold. The change that
/// revises the log wording deletes this file.
library;

import '../domain/connection_failure.dart';
import '../domain/link_end.dart';
import '../domain/link_operation.dart';
import '../domain/link_phase.dart';

/// The context every line of Connection's lifecycle is logged under.
const connectionLogContext = 'bluey.connection';

/// The context the MTU request and the link's readings are logged under,
/// the one GATT operations have always shared.
const gattLogContext = 'bluey.gatt';

/// The word a `state transition` line names for a link entering [phase].
String stateWordOf(LinkPhase phase) => switch (phase) {
  Linked() => 'ConnectionState.linked',
  Ready() => 'ConnectionState.ready',
  Closing() => 'ConnectionState.disconnecting',
  Ended(end: EndedByRadioOutage()) => 'ConnectionState.invalidated',
  Ended() => 'ConnectionState.disconnected',
};

/// The word logs and exception messages name [operation] by, the platform
/// call's name an app has always read for it.
String operationWordOf(LinkOperation operation) => switch (operation) {
  LinkOperation.open => 'connect',
  LinkOperation.close => 'disconnect',
  LinkOperation.negotiateMtu => 'requestMtu',
  LinkOperation.readWritePayloadLimit => 'getMaximumWriteLength',
  LinkOperation.readSignalStrength => 'readRssi',
  LinkOperation.readBondState => 'bondState',
  LinkOperation.followBondState => 'bondStateChanges',
  LinkOperation.bond => 'bond',
  LinkOperation.removeBond => 'removeBond',
};

/// The code a log line names [failure] by, the class name an app has always
/// read for it, so renaming a failure changes no line.
String failureCodeOf(ConnectionFailure failure) => switch (failure) {
  ConnectFailed() => 'ConnectFailed',
  LinkHadEnded() => 'LinkEnded',
  RadioUnavailable() => 'RadioUnavailable',
  PermissionMissing() => 'PermissionMissing',
  OperationTimedOut() => 'OperationTimedOut',
  OperationRejected() => 'OperationRejected',
  UnexpectedPlatformFailure() => 'UnexpectedPlatformFailure',
  FeatureUnsupported() => 'FeatureUnsupported',
  MtuAboveMaximum() => 'MtuAboveMaximum',
};

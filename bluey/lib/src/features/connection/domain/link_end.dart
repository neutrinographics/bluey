import 'package:meta/meta.dart';

/// What made the radio unusable, which ends every link at once whatever
/// each link was doing.
enum RadioOutage { off, unauthorized, unsupported, unknown }

/// Why a link ended. An ended link always carries one, so whoever reads the
/// end can tell a disconnect the app asked for from a lost link.
@immutable
sealed class LinkEnd {
  const LinkEnd();
}

/// The link ended because a disconnect was asked for.
final class EndedOnRequest extends LinkEnd {
  const EndedOnRequest();

  @override
  bool operator ==(Object other) => other is EndedOnRequest;

  @override
  int get hashCode => (EndedOnRequest).hashCode;
}

/// The link was lost, or the radio closed it, without anyone asking.
final class EndedByDrop extends LinkEnd {
  const EndedByDrop();

  @override
  bool operator ==(Object other) => other is EndedByDrop;

  @override
  int get hashCode => (EndedByDrop).hashCode;
}

/// The radio became unusable while the link was open, so the link cannot be
/// trusted to exist any more.
final class EndedByRadioOutage extends LinkEnd {
  const EndedByRadioOutage(this.outage);

  /// What made the radio unusable.
  final RadioOutage outage;

  @override
  bool operator ==(Object other) =>
      other is EndedByRadioOutage && other.outage == outage;

  @override
  int get hashCode => Object.hash(EndedByRadioOutage, outage);
}

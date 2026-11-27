import 'package:meta/meta.dart';

import '../../../shared/domain/device_address.dart';
import 'link_end.dart';

/// Something that happened to a device's link, which Connection tells
/// others of in its own words, so each audience can word it as it reads it.
@immutable
sealed class LinkEvent {
  const LinkEvent({required this.device, required this.at});

  /// The device whose link it is.
  final DeviceAddress device;

  /// When it happened.
  final DateTime at;

  bool _sameAs(LinkEvent other) =>
      other.runtimeType == runtimeType &&
      other.device == device &&
      other.at == at;
}

/// An open of a link to [device] began, raised as the link begins, before
/// the radio answers whether the open succeeded.
final class LinkOpenBegan extends LinkEvent {
  const LinkOpenBegan({required super.device, required super.at});

  @override
  bool operator ==(Object other) => other is LinkOpenBegan && _sameAs(other);

  @override
  int get hashCode => Object.hash(LinkOpenBegan, device, at);
}

/// The link to [device] opened.
final class LinkOpened extends LinkEvent {
  const LinkOpened({required super.device, required super.at});

  @override
  bool operator ==(Object other) => other is LinkOpened && _sameAs(other);

  @override
  int get hashCode => Object.hash(LinkOpened, device, at);
}

/// The link to [device] ended, for good, and [end] says why.
final class LinkEnded extends LinkEvent {
  const LinkEnded({
    required super.device,
    required super.at,
    required this.end,
  });

  /// Why the link ended.
  final LinkEnd end;

  @override
  bool operator ==(Object other) =>
      other is LinkEnded && _sameAs(other) && other.end == end;

  @override
  int get hashCode => Object.hash(LinkEnded, device, at, end);
}

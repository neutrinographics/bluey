import 'package:meta/meta.dart';

/// Properties that describe what operations a characteristic supports.
///
/// This is a value object representing the GATT characteristic properties
/// flags as defined by the Bluetooth specification.
@immutable
class CharacteristicProperties {
  /// Whether the characteristic value can be read.
  final bool canRead;

  /// Whether the characteristic value can be written with response.
  final bool canWrite;

  /// Whether the characteristic value can be written without response.
  final bool canWriteWithoutResponse;

  /// Whether the characteristic supports notifications.
  final bool canNotify;

  /// Whether the characteristic supports indications.
  final bool canIndicate;

  /// Creates characteristic properties with the specified flags.
  const CharacteristicProperties({
    this.canRead = false,
    this.canWrite = false,
    this.canWriteWithoutResponse = false,
    this.canNotify = false,
    this.canIndicate = false,
  });

  /// Creates characteristic properties from Bluetooth GATT flags.
  ///
  /// The flags are as defined in the Bluetooth specification:
  /// - Bit 1 (0x02): Read
  /// - Bit 2 (0x04): Write Without Response
  /// - Bit 3 (0x08): Write
  /// - Bit 4 (0x10): Notify
  /// - Bit 5 (0x20): Indicate
  factory CharacteristicProperties.fromFlags(int flags) {
    return CharacteristicProperties(
      canRead: (flags & 0x02) != 0,
      canWriteWithoutResponse: (flags & 0x04) != 0,
      canWrite: (flags & 0x08) != 0,
      canNotify: (flags & 0x10) != 0,
      canIndicate: (flags & 0x20) != 0,
    );
  }

  /// Whether the characteristic supports any write operation.
  bool get canWriteAny => canWrite || canWriteWithoutResponse;

  /// Whether the characteristic supports notifications or indications.
  bool get canSubscribe => canNotify || canIndicate;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CharacteristicProperties &&
        other.canRead == canRead &&
        other.canWrite == canWrite &&
        other.canWriteWithoutResponse == canWriteWithoutResponse &&
        other.canNotify == canNotify &&
        other.canIndicate == canIndicate;
  }

  @override
  int get hashCode => Object.hash(
    canRead,
    canWrite,
    canWriteWithoutResponse,
    canNotify,
    canIndicate,
  );

  @override
  String toString() {
    return 'CharacteristicProperties('
        'canRead: $canRead, '
        'canWrite: $canWrite, '
        'canWriteWithoutResponse: $canWriteWithoutResponse, '
        'canNotify: $canNotify, '
        'canIndicate: $canIndicate)';
  }
}

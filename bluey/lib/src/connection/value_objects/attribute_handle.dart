import 'package:meta/meta.dart';

/// A GATT attribute handle.
///
/// Wraps a positive integer that identifies a GATT attribute (such as a
/// characteristic or descriptor) on a remote device. The wire-level type
/// remains `int`; this value object exists purely on the Dart domain side
/// to prevent accidentally passing arbitrary integers (for example a
/// device id) where a handle is expected.
@immutable
class AttributeHandle {
  final int value;

  AttributeHandle(this.value) {
    if (value <= 0) {
      throw ArgumentError('attribute handle must be positive: $value');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AttributeHandle && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'AttributeHandle($value)';
}

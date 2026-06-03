import 'dart:typed_data';

/// Outcome of comparing a chunked transfer's reassembled read-back bytes
/// against the deterministic pattern (`byte[i] = i & 0xff`) the client
/// sent. Pure value object — no I/O, fully unit-testable.
class TransferVerdict {
  /// True when every byte matched and the lengths were equal.
  final bool ok;

  /// Offset of the first mismatch (a differing byte, or the truncation /
  /// overrun point when one side ran out first). Null when [ok].
  final int? firstDivergenceOffset;

  /// The pattern byte expected at [firstDivergenceOffset], or null when
  /// the read-back overran the expected length (nothing was expected
  /// there).
  final int? expectedByte;

  /// The byte actually present at [firstDivergenceOffset], or null when
  /// the read-back was truncated (nothing arrived there).
  final int? gotByte;

  /// The logical payload length the client sent.
  final int expectedLen;

  /// The length actually read back from the server.
  final int gotLen;

  const TransferVerdict._({
    required this.ok,
    required this.expectedLen,
    required this.gotLen,
    this.firstDivergenceOffset,
    this.expectedByte,
    this.gotByte,
  });

  factory TransferVerdict.ok({required int len}) =>
      TransferVerdict._(ok: true, expectedLen: len, gotLen: len);

  factory TransferVerdict.diverged({
    required int offset,
    required int? expectedByte,
    required int? gotByte,
    required int expectedLen,
    required int gotLen,
  }) => TransferVerdict._(
    ok: false,
    firstDivergenceOffset: offset,
    expectedByte: expectedByte,
    gotByte: gotByte,
    expectedLen: expectedLen,
    gotLen: gotLen,
  );

  /// Human-readable one-liner for the result panel / failure messages.
  String describe() {
    if (ok) return 'OK ($expectedLen bytes)';
    String hex(int? b) =>
        b == null ? '--' : '0x${b.toRadixString(16).padLeft(2, '0')}';
    return 'offset $firstDivergenceOffset: expected ${hex(expectedByte)} '
        'got ${hex(gotByte)} (len $expectedLen vs $gotLen)';
  }
}

/// Compares [readBack] against the deterministic pattern `byte[i] = i & 0xff`
/// of length [expectedLen]. Returns [TransferVerdict.ok] when every byte
/// matches and the lengths are equal; otherwise the first point of
/// divergence — a differing byte, or (if the bytes matched up to the
/// shorter length) the truncation / overrun offset.
TransferVerdict evaluateTransfer({
  required int expectedLen,
  required Uint8List readBack,
}) {
  final common = expectedLen < readBack.length ? expectedLen : readBack.length;
  for (var i = 0; i < common; i++) {
    final expected = i & 0xff;
    if (readBack[i] != expected) {
      return TransferVerdict.diverged(
        offset: i,
        expectedByte: expected,
        gotByte: readBack[i],
        expectedLen: expectedLen,
        gotLen: readBack.length,
      );
    }
  }
  if (readBack.length != expectedLen) {
    return TransferVerdict.diverged(
      offset: common,
      expectedByte: common < expectedLen ? (common & 0xff) : null,
      gotByte: common < readBack.length ? readBack[common] : null,
      expectedLen: expectedLen,
      gotLen: readBack.length,
    );
  }
  return TransferVerdict.ok(len: expectedLen);
}

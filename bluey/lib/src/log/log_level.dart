/// Severity levels for [BlueyLogEvent]s.
///
/// Declared in ascending severity order so that `level.index` doubles as a
/// numeric severity suitable for threshold comparisons (e.g. a logger with
/// `minLevel = info` drops everything where `level.index < info.index`).
enum BlueyLogLevel {
  /// Highly detailed protocol-level traces. Off by default.
  trace,

  /// Diagnostic information useful when investigating issues.
  debug,

  /// Routine, expected lifecycle events.
  info,

  /// Recoverable problems or unexpected-but-handled conditions.
  warn,

  /// Errors that surface to callers or indicate broken invariants.
  error,
}

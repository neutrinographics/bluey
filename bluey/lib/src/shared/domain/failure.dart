/// What a unit answers, as a value, when an operation cannot do what was asked.
///
/// Callers read a failure to decide what to do next, so a failure is returned
/// in a [Left] rather than raised: the signature tells the caller it can fail.
abstract interface class Failure {
  /// A sentence for a person or a log, never parsed by callers.
  String get message;
}

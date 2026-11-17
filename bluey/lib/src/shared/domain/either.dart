/// One of two answers, so an operation that can fail says so in its signature
/// instead of raising.
///
/// By convention a [Left] holds the failure and a [Right] the success.
sealed class Either<L, R> {
  const Either();

  /// Reads the answer whichever side it is on, so a caller must handle both.
  T fold<T>(T Function(L left) onLeft, T Function(R right) onRight) =>
      switch (this) {
        Left<L, R>(:final value) => onLeft(value),
        Right<L, R>(:final value) => onRight(value),
      };

  /// Changes a success and leaves a failure as it is.
  Either<L, T> map<T>(T Function(R right) transform) => switch (this) {
    Left<L, R>(:final value) => Left<L, T>(value),
    Right<L, R>(:final value) => Right<L, T>(transform(value)),
  };
}

/// The failing side of an [Either]; equal to any [Left] of an equal value.
final class Left<L, R> extends Either<L, R> {
  const Left(this.value);

  final L value;

  @override
  bool operator ==(Object other) => other is Left && other.value == value;

  @override
  int get hashCode => Object.hash(Left, value);

  @override
  String toString() => 'Left($value)';
}

/// The succeeding side of an [Either]; equal to any [Right] of an equal value.
final class Right<L, R> extends Either<L, R> {
  const Right(this.value);

  final R value;

  @override
  bool operator ==(Object other) => other is Right && other.value == value;

  @override
  int get hashCode => Object.hash(Right, value);

  @override
  String toString() => 'Right($value)';
}

/// Chains a step that can itself fail.
///
/// An extension rather than a member: a member's parameter type would be fixed
/// by the receiver's left type, so a caller holding an `Either<ConnectionFailure,
/// T>` as an `Either<Failure, T>` would fail at run time when its next step
/// answered a different failure.
extension EitherFlatMap<L, R> on Either<L, R> {
  /// Runs [next] on a success and stops at the first failure.
  Either<L, T> flatMap<T>(Either<L, T> Function(R right) next) =>
      switch (this) {
        Left<L, R>(:final value) => Left<L, T>(value),
        Right<L, R>(:final value) => next(value),
      };
}

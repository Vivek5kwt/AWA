class Left<L, R> extends Either<L, R> {
  final L value;
  const Left(this.value);

  @override
  B fold<B>(B Function(L l) ifLeft, B Function(R r) ifRight) {
    return ifLeft(value);
  }

  @override
  String toString() => 'Left($value)';
}

// Define a class to represent the Right side of Either
class Right<L, R> extends Either<L, R> {
  final R value;
  const Right(this.value);

  @override
  B fold<B>(B Function(L l) ifLeft, B Function(R r) ifRight) {
    return ifRight(value);
  }

  @override
  String toString() => 'Right($value)';
}

// The base Either class
abstract class Either<L, R> {
  const Either();

  // Fold method to handle both Left and Right cases
  B fold<B>(B Function(L l) ifLeft, B Function(R r) ifRight);

  // Utility methods
  bool isLeft() => this is Left<L, R>;
  bool isRight() => this is Right<L, R>;

  L? getLeft() => isLeft() ? (this as Left<L, R>).value : null;
  R? getRight() => isRight() ? (this as Right<L, R>).value : null;

  @override
  String toString();
}

// Utility functions to create Left and Right instances
Either<L, R> left<L, R>(L value) => Left<L, R>(value);
Either<L, R> right<L, R>(R value) => Right<L, R>(value);

// Extension methods for better readability and chaining
extension EitherExtensions<L, R> on Either<L, R> {
  Either<L, R> ifLeft(void Function(L l) action) {
    if (isLeft()) action((this as Left<L, R>).value);
    return this;
  }

  Either<L, R> ifRight(void Function(R r) action) {
    if (isRight()) action((this as Right<L, R>).value);
    return this;
  }

  Either<L2, R> mapLeft<L2>(L2 Function(L l) transform) {
    return fold(
          (l) => left(transform(l)),
          (r) => right(r),
    );
  }

  Either<L, R2> mapRight<R2>(R2 Function(R r) transform) {
    return fold(
          (l) => left(l),
          (r) => right(transform(r)),
    );
  }
}
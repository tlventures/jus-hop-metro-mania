sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T data) success,
    required R Function(Failure failure) onFailure,
  }) => switch (this) {
    Success(:final data) => success(data),
    Error(:final failure) => onFailure(failure),
  };

  R? whenOrNull<R>({
    R Function(T data)? success,
    R Function(Failure failure)? failure,
  }) =>
      when(success: success ?? (_) => null, onFailure: failure ?? (_) => null);

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Error<T>;

  T? getOrNull() => whenOrNull(success: (data) => data);
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

final class Error<T> extends Result<T> {
  final Failure failure;
  const Error(this.failure);
}

sealed class Failure {
  const Failure();
}

final class NetworkFailure extends Failure {
  final String message;
  const NetworkFailure(this.message);
}

final class ServerFailure extends Failure {
  final int statusCode;
  final String message;
  const ServerFailure(this.statusCode, this.message);
}

final class CacheFailure extends Failure {
  final String message;
  const CacheFailure(this.message);
}

final class ValidationFailure extends Failure {
  final String message;
  const ValidationFailure(this.message);
}

final class UnknownFailure extends Failure {
  final String message;
  const UnknownFailure(this.message);
}

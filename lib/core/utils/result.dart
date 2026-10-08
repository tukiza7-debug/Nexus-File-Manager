/// Lightweight functional error handling used across all layers.
sealed class Result<T> {
  const Result();

  bool get ok => this is Ok<T>;
  T? get value => this is Ok<T> ? (this as Ok<T>).data : null;
  String? get error => this is Err<T> ? (this as Err<T>).message : null;

  T unwrap() => switch (this) {
        Ok<T>(:final data) => data,
        Err<T>(:final message) => throw StateError(message),
      };

  R fold<R>(R Function(T data) onOk, R Function(String msg) onErr) =>
      switch (this) {
        Ok<T>(:final data) => onOk(data),
        Err<T>(:final message) => onErr(message),
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.data);
  final T data;
}

class Err<T> extends Result<T> {
  const Err(this.message);
  final String message;
}

/// Base class for typed application errors surfaced to the UI as toasts.
class NexusException implements Exception {
  const NexusException(this.message, {this.detail});
  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message: $detail';
}

class FrozenException extends NexusException {
  const FrozenException(String path)
      : super('Item is frozen and cannot be modified', detail: path);
}

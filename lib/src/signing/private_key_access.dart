import 'dart:typed_data';

/// Synchronous, narrowly-scoped access to private-key bytes.
///
/// Implementations must provide a disposable copy and erase it immediately
/// after [operation] returns. Keeping the callback synchronous prevents key
/// material from crossing an asynchronous suspension point.
abstract interface class PrivateKeyAccess {
  T usePrivateKey<T>(T Function(Uint8List privateKey) operation);
}

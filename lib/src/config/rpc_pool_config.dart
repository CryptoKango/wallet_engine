import '../error/wallet_error.dart';
import 'rpc_endpoint.dart';

/// Strategy used to select an endpoint from an RPC pool.
enum RpcSelectionStrategy { priorityFailover, roundRobin }

/// Immutable RPC pool configuration.
final class RpcPoolConfig {
  RpcPoolConfig({
    required List<RpcEndpoint> endpoints,
    this.strategy = RpcSelectionStrategy.priorityFailover,
  }) : endpoints = List<RpcEndpoint>.unmodifiable(endpoints) {
    if (endpoints.isEmpty) {
      throw const WalletValidationException(
        field: 'endpoints',
        message: 'RPC endpoint pool must not be empty.',
      );
    }

    final uris = endpoints.map((endpoint) => endpoint.uri).toSet();
    if (uris.length != endpoints.length) {
      throw const WalletValidationException(
        field: 'endpoints',
        message: 'RPC endpoint pool must not contain duplicate URIs.',
      );
    }
  }

  final List<RpcEndpoint> endpoints;
  final RpcSelectionStrategy strategy;
}

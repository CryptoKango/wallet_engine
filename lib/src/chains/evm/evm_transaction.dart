import 'package:decimal/decimal.dart';

import '../../error/wallet_error.dart';
import '../../signing/transaction_signer.dart';
import 'evm_fee_quote.dart';

/// Host intent used to prepare an EVM transaction through RPC.
final class EvmTransactionRequest {
  EvmTransactionRequest({
    required this.from,
    required this.to,
    Decimal? value,
    this.data,
    this.nonce,
    this.gasLimit,
    this.feeQuote,
  }) : value = value ?? Decimal.zero,
       assert(from != '', 'from must not be empty'),
       assert(to != '', 'to must not be empty'),
       assert(
         value == null || value >= Decimal.zero,
         'value must not be negative',
       ),
       assert(nonce == null || !nonce.isNegative, 'nonce must not be negative'),
       assert(
         gasLimit == null || !gasLimit.isNegative,
         'gasLimit must not be negative',
       );

  final String from;
  final String to;

  /// User-facing native amount in whole-token decimal units.
  final Decimal value;

  /// Hex calldata, with or without the `0x` prefix.
  final String? data;
  final BigInt? nonce;
  final BigInt? gasLimit;
  final EvmFeeQuote? feeQuote;
}

/// Fully prepared EVM transaction. It contains no private-key material.
final class EvmUnsignedTransaction {
  EvmUnsignedTransaction.legacy({
    required this.chainId,
    required this.nonce,
    required this.gasLimit,
    required this.to,
    required BigInt gasPrice,
    BigInt? valueBaseUnits,
    this.data,
  }) : gasPrice = gasPrice,
       maxPriorityFeePerGas = null,
       maxFeePerGas = null,
       valueBaseUnits = valueBaseUnits ?? BigInt.zero,
       assert(!chainId.isNegative, 'chainId must not be negative'),
       assert(!nonce.isNegative, 'nonce must not be negative'),
       assert(!gasLimit.isNegative, 'gasLimit must not be negative'),
       assert(to != '', 'to must not be empty'),
       assert(!gasPrice.isNegative, 'gasPrice must not be negative'),
       assert(
         valueBaseUnits == null || !valueBaseUnits.isNegative,
         'valueBaseUnits must not be negative',
       );

  EvmUnsignedTransaction.eip1559({
    required this.chainId,
    required this.nonce,
    required this.gasLimit,
    required this.to,
    required BigInt maxPriorityFeePerGas,
    required BigInt maxFeePerGas,
    BigInt? valueBaseUnits,
    this.data,
  }) : gasPrice = null,
       maxPriorityFeePerGas = maxPriorityFeePerGas,
       maxFeePerGas = maxFeePerGas,
       valueBaseUnits = valueBaseUnits ?? BigInt.zero,
       assert(!chainId.isNegative, 'chainId must not be negative'),
       assert(!nonce.isNegative, 'nonce must not be negative'),
       assert(!gasLimit.isNegative, 'gasLimit must not be negative'),
       assert(to != '', 'to must not be empty'),
       assert(
         !maxPriorityFeePerGas.isNegative,
         'maxPriorityFeePerGas must not be negative',
       ),
       assert(!maxFeePerGas.isNegative, 'maxFeePerGas must not be negative'),
       assert(
         valueBaseUnits == null || !valueBaseUnits.isNegative,
         'valueBaseUnits must not be negative',
       );

  final BigInt chainId;
  final BigInt nonce;
  final BigInt gasLimit;
  final String to;

  /// Protocol-level native amount in wei-like base units.
  final BigInt valueBaseUnits;

  /// Hex calldata, with or without the `0x` prefix.
  final String? data;
  final BigInt? gasPrice;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? maxFeePerGas;

  bool get isEip1559 => maxFeePerGas != null;
}

/// Signed EVM transaction ready for `eth_sendRawTransaction`.
final class EvmSignedTransaction {
  EvmSignedTransaction(String rawTransaction)
    : rawTransaction = _normalize(rawTransaction);

  final String rawTransaction;

  static String _normalize(String value) {
    final trimmed = value.trim();
    final payload = trimmed.startsWith('0x') || trimmed.startsWith('0X')
        ? trimmed.substring(2)
        : trimmed;
    if (payload.isEmpty ||
        payload.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(payload)) {
      throw const WalletValidationException(
        field: 'rawTransaction',
        message: 'Raw transaction must be non-empty, even-length hex data.',
      );
    }
    return '0x$payload';
  }
}

/// EVM-specific signing boundary. UKey/MPC implementations can implement this
/// interface without exposing key material to the engine.
abstract interface class EvmTransactionSigner
    implements
        TransactionSigner<EvmUnsignedTransaction, EvmSignedTransaction> {}

/// Result returned after signing and broadcasting.
final class EvmBroadcastResult {
  const EvmBroadcastResult({
    required this.transactionHash,
    required this.signedTransaction,
  });

  final String transactionHash;
  final EvmSignedTransaction signedTransaction;
}

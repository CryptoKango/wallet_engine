import 'package:decimal/decimal.dart';

/// Solana token program used to derive and query associated token accounts.
enum SolanaTokenProgram {
  token('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
  token2022('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb');

  const SolanaTokenProgram(this.programId);

  final String programId;

  static SolanaTokenProgram? tryFromProgramId(String value) {
    for (final program in values) {
      if (program.programId == value) return program;
    }
    return null;
  }
}

enum SolanaTokenAccountState { uninitialized, initialized, frozen, unknown }

/// Exact amount returned by Solana token-account RPC methods.
final class SolanaTokenAmount {
  const SolanaTokenAmount({
    required this.baseUnits,
    required this.decimals,
    required this.amount,
  });

  final BigInt baseUnits;
  final int decimals;
  final Decimal amount;
}

/// Parsed SPL Token or Token-2022 account.
final class SolanaTokenAccount {
  const SolanaTokenAccount({
    required this.address,
    required this.owner,
    required this.mint,
    required this.program,
    required this.tokenAmount,
    required this.state,
    required this.isAssociated,
    required this.isNative,
    this.delegate,
    this.closeAuthority,
  });

  final String address;
  final String owner;
  final String mint;
  final SolanaTokenProgram program;
  final SolanaTokenAmount tokenAmount;
  final SolanaTokenAccountState state;

  /// Whether [address] is the canonical ATA derived from owner, mint, and
  /// token program.
  final bool isAssociated;

  final bool isNative;
  final String? delegate;
  final String? closeAuthority;
}

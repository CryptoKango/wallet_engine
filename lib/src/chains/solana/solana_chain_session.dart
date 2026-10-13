import 'package:decimal/decimal.dart';
import 'package:on_chain/on_chain.dart'
    show AssociatedTokenAccountProgramUtils, SolAddress;

import '../../amount/amount_codec.dart';
import '../../chain/chain_network_identity.dart';
import '../../chain/chain_session.dart';
import '../../config/wallet_chain_config.dart';
import '../../core/wallet_engine_exception.dart';
import '../../error/wallet_error.dart';
import '../../rpc/json_rpc_client.dart';
import '../../rpc/json_rpc_exception.dart';
import '../../transaction/transaction_confirmation.dart';
import 'solana_token_account.dart';
import 'solana_transaction.dart';
import 'solana_transaction_receipt.dart';

final class SolanaChainSession
    implements ChainSession, ChainNetworkIdentityVerifier {
  factory SolanaChainSession({
    required WalletChainConfig config,
    required JsonRpcClient rpc,
  }) {
    return SolanaChainSession._(config, rpc);
  }

  const SolanaChainSession._(this.config, this._rpc);

  @override
  final WalletChainConfig config;
  final JsonRpcClient _rpc;

  Future<Decimal> getBalance(String address) {
    return _rpc.call<Decimal>(
      method: 'getBalance',
      params: <Object?>[
        address,
        const <String, Object?>{'commitment': 'confirmed'},
      ],
      decode: (result) => AmountCodec.fromBaseUnits(
        _bigInt(_map(result)['value']),
        decimals: config.nativeDecimals,
      ),
    );
  }

  Future<String> getLatestBlockhash() {
    return _rpc.call<String>(
      method: 'getLatestBlockhash',
      params: const <Object?>[
        <String, Object?>{'commitment': 'confirmed'},
      ],
      decode: (result) {
        final value = _map(_map(result)['value']);
        return _string(value['blockhash']);
      },
    );
  }

  Future<String> getGenesisHash() {
    return _rpc.call<String>(method: 'getGenesisHash', decode: _string);
  }

  @override
  Future<ChainNetworkIdentity> verifyNetworkIdentity() async {
    final configured = config.chainId;
    if (configured == null) {
      throw const WalletValidationException(
        field: 'chainId',
        message: 'Solana network verification requires a genesis hash.',
      );
    }
    final observed = await getGenesisHash();
    if (configured != observed) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.networkMismatch,
        message: 'Configured Solana genesis hash does not match the RPC node.',
        context: <String, Object?>{
          'chainKey': config.key,
          'configuredChainId': configured,
          'observedChainId': observed,
        },
      );
    }
    return ChainNetworkIdentity(
      family: config.family,
      configured: configured,
      observed: observed,
    );
  }

  Future<BigInt> getMinimumBalanceForRentExemption(int size) {
    return _rpc.call<BigInt>(
      method: 'getMinimumBalanceForRentExemption',
      params: <Object?>[size],
      decode: _bigInt,
    );
  }

  Future<BigInt?> getRecentPriorityFeeP75() {
    return _rpc.call<BigInt?>(
      method: 'getRecentPrioritizationFees',
      decode: (result) {
        final list = _list(result);
        if (list.isEmpty) return null;
        final values =
            list
                .map((item) => _bigInt(_map(item)['prioritizationFee']))
                .toList()
              ..sort();
        return values[((values.length - 1) * 3) ~/ 4];
      },
    );
  }

  /// Derives the canonical associated token account without RPC or native FFI.
  String deriveAssociatedTokenAddress({
    required String owner,
    required String mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
    bool allowOwnerOffCurve = false,
  }) {
    final ownerAddress = _address(owner, field: 'owner');
    final mintAddress = _address(mint, field: 'mint');
    if (!allowOwnerOffCurve && !ownerAddress.isOnCurve) {
      throw const WalletValidationException(
        field: 'owner',
        message: 'Solana ATA owner must be on curve.',
      );
    }
    return AssociatedTokenAccountProgramUtils.associatedTokenAccount(
      owner: ownerAddress,
      mint: mintAddress,
      tokenProgramId: SolAddress(program.programId),
      allowOwnerOffCurve: allowOwnerOffCurve,
    ).address.address;
  }

  /// Lists parsed token accounts owned by [owner].
  ///
  /// When [mint] is supplied, the RPC query is mint-filtered and results are
  /// still checked against [program]. Otherwise the token program is used as
  /// the RPC filter. The returned list is immutable.
  Future<List<SolanaTokenAccount>> getTokenAccountsByOwner({
    required String owner,
    String? mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
  }) {
    final normalizedOwner = owner.trim();
    _address(normalizedOwner, field: 'owner');
    final normalizedMint = mint?.trim();
    if (normalizedMint != null) {
      _address(normalizedMint, field: 'mint');
    }
    return _rpc.call<List<SolanaTokenAccount>>(
      method: 'getTokenAccountsByOwner',
      params: <Object?>[
        normalizedOwner,
        <String, Object?>{
          if (normalizedMint != null)
            'mint': normalizedMint
          else
            'programId': program.programId,
        },
        const <String, Object?>{
          'encoding': 'jsonParsed',
          'commitment': 'confirmed',
        },
      ],
      decode: (result) {
        final values = _list(_map(result)['value']);
        final accounts = <SolanaTokenAccount>[];
        for (final value in values) {
          final item = _map(value);
          final address = _string(item['pubkey']);
          final account = _decodeTokenAccount(
            address: address,
            account: _map(item['account']),
          );
          if (account.program != program ||
              account.owner != normalizedOwner ||
              (normalizedMint != null && account.mint != normalizedMint)) {
            throw const JsonRpcException(
              message: 'Solana RPC returned a mismatched token account.',
              retryable: true,
            );
          }
          accounts.add(account);
        }
        return List<SolanaTokenAccount>.unmodifiable(accounts);
      },
    );
  }

  /// Returns the sum of all matching token accounts owned by [owner].
  Future<Decimal> getTokenBalance({
    required String owner,
    required String mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
  }) async {
    final accounts = await getTokenAccountsByOwner(
      owner: owner,
      mint: mint,
      program: program,
    );
    return accounts.fold<Decimal>(
      Decimal.zero,
      (total, account) => total + account.tokenAmount.amount,
    );
  }

  /// Returns the first matching token account for backward compatibility.
  ///
  /// Use [getAssociatedTokenAccount] when the caller requires the canonical
  /// ATA, or [getTokenAccountsByOwner] when multiple accounts are meaningful.
  Future<String?> getTokenAccountAddress({
    required String owner,
    required String mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
  }) async {
    final accounts = await getTokenAccountsByOwner(
      owner: owner,
      mint: mint,
      program: program,
    );
    return accounts.isEmpty ? null : accounts.first.address;
  }

  /// Queries and validates the canonical associated token account.
  Future<SolanaTokenAccount?> getAssociatedTokenAccount({
    required String owner,
    required String mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
    bool allowOwnerOffCurve = false,
  }) {
    final normalizedOwner = owner.trim();
    final normalizedMint = mint.trim();
    final address = deriveAssociatedTokenAddress(
      owner: normalizedOwner,
      mint: normalizedMint,
      program: program,
      allowOwnerOffCurve: allowOwnerOffCurve,
    );
    return _rpc.call<SolanaTokenAccount?>(
      method: 'getAccountInfo',
      params: <Object?>[
        address,
        const <String, Object?>{
          'encoding': 'jsonParsed',
          'commitment': 'confirmed',
        },
      ],
      decode: (result) {
        final value = _map(result)['value'];
        if (value == null) return null;
        final account = _decodeTokenAccount(
          address: address,
          account: _map(value),
        );
        if (!account.isAssociated ||
            account.owner != normalizedOwner ||
            account.mint != normalizedMint ||
            account.program != program) {
          throw const JsonRpcException(
            message: 'Solana RPC returned an invalid associated token account.',
            retryable: true,
          );
        }
        return account;
      },
    );
  }

  Future<bool> associatedTokenAccountExists({
    required String owner,
    required String mint,
    SolanaTokenProgram program = SolanaTokenProgram.token,
    bool allowOwnerOffCurve = false,
  }) async {
    return await getAssociatedTokenAccount(
          owner: owner,
          mint: mint,
          program: program,
          allowOwnerOffCurve: allowOwnerOffCurve,
        ) !=
        null;
  }

  /// Queries the exact amount held by a token-account address.
  Future<SolanaTokenAmount> getTokenAccountBalance(String address) {
    _address(address, field: 'address');
    return _rpc.call<SolanaTokenAmount>(
      method: 'getTokenAccountBalance',
      params: <Object?>[
        address,
        const <String, Object?>{'commitment': 'confirmed'},
      ],
      decode: (result) => _decodeTokenAmount(_map(result)['value']),
    );
  }

  Future<String> broadcast(SolanaSignedTransaction transaction) {
    return _rpc.call<String>(
      method: 'sendTransaction',
      params: <Object?>[
        transaction.base64Transaction,
        const <String, Object?>{'encoding': 'base64', 'skipPreflight': false},
      ],
      decode: _string,
    );
  }

  Future<SolanaTransactionReceipt?> getTransactionReceipt(String signature) {
    return _rpc.call<SolanaTransactionReceipt?>(
      method: 'getSignatureStatuses',
      params: <Object?>[
        <String>[signature],
        const <String, Object?>{'searchTransactionHistory': true},
      ],
      decode: (result) {
        final statuses = _list(_map(result)['value']);
        if (statuses.isEmpty || statuses.first == null) return null;
        final status = _map(statuses.first);
        return SolanaTransactionReceipt(
          signature: signature,
          slot: _intOrNull(status['slot']),
          confirmationStatus: status['confirmationStatus'] as String?,
          success: status['err'] == null,
        );
      },
    );
  }

  Future<SolanaTransactionReceipt> waitForTransactionReceipt(
    String signature, {
    SolanaConfirmationLevel confirmation = SolanaConfirmationLevel.finalized,
    TransactionConfirmationPolicy policy =
        const TransactionConfirmationPolicy(),
    WalletCancellationToken? cancellationToken,
  }) {
    return TransactionConfirmationWaiter.wait<SolanaTransactionReceipt>(
      lookup: () => getTransactionReceipt(signature),
      isConfirmed: (receipt) =>
          _confirmationRank(receipt.confirmationStatus) >= confirmation.index,
      transactionId: signature,
      chainKey: config.key,
      policy: policy,
      cancellationToken: cancellationToken,
    );
  }

  Future<String> signAndBroadcast(
    SolanaUnsignedTransaction transaction, {
    required SolanaTransactionSigner signer,
  }) async {
    return broadcast(await signer.sign(transaction));
  }

  @override
  Future<void> close() async {}

  static Map<Object?, Object?> _map(Object? value) {
    if (value is Map<Object?, Object?>) return value;
    throw const JsonRpcException(
      message: 'Expected a Solana RPC object.',
      retryable: true,
    );
  }

  static List<Object?> _list(Object? value) {
    if (value is List<Object?>) return value;
    throw const JsonRpcException(
      message: 'Expected a Solana RPC list.',
      retryable: true,
    );
  }

  static String _string(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    throw const JsonRpcException(
      message: 'Expected a Solana RPC string.',
      retryable: true,
    );
  }

  static BigInt _bigInt(Object? value) {
    if (value is int) return BigInt.from(value);
    if (value is String) {
      final parsed = BigInt.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const JsonRpcException(
      message: 'Expected a Solana RPC integer.',
      retryable: true,
    );
  }

  static int? _intOrNull(Object? value) {
    return value is int ? value : int.tryParse(value?.toString() ?? '');
  }

  SolanaTokenAccount _decodeTokenAccount({
    required String address,
    required Map<Object?, Object?> account,
  }) {
    final programId = _string(account['owner']);
    final program = SolanaTokenProgram.tryFromProgramId(programId);
    if (program == null) {
      throw const JsonRpcException(
        message: 'Solana RPC returned an unsupported token program.',
        retryable: true,
      );
    }
    final data = _map(account['data']);
    final parsed = _map(data['parsed']);
    if (parsed['type'] != 'account') {
      throw const JsonRpcException(
        message: 'Solana RPC returned a non-token account.',
        retryable: true,
      );
    }
    final info = _map(parsed['info']);
    final owner = _string(info['owner']);
    final mint = _string(info['mint']);
    final expectedAddress = deriveAssociatedTokenAddress(
      owner: owner,
      mint: mint,
      program: program,
      allowOwnerOffCurve: true,
    );
    return SolanaTokenAccount(
      address: address,
      owner: owner,
      mint: mint,
      program: program,
      tokenAmount: _decodeTokenAmount(info['tokenAmount']),
      state: _tokenAccountState(info['state']),
      isAssociated: expectedAddress == address,
      isNative: info['isNative'] == true,
      delegate: _optionalString(info['delegate']),
      closeAuthority: _optionalString(info['closeAuthority']),
    );
  }

  static SolanaTokenAmount _decodeTokenAmount(Object? value) {
    final amount = _map(value);
    final baseUnits = _bigInt(amount['amount']);
    final decimals = _intOrNull(amount['decimals']);
    if (decimals == null || decimals < 0) {
      throw const JsonRpcException(
        message: 'Solana RPC returned invalid token decimals.',
        retryable: true,
      );
    }
    return SolanaTokenAmount(
      baseUnits: baseUnits,
      decimals: decimals,
      amount: AmountCodec.fromBaseUnits(baseUnits, decimals: decimals),
    );
  }

  static SolanaTokenAccountState _tokenAccountState(Object? value) {
    return switch (value) {
      'uninitialized' => SolanaTokenAccountState.uninitialized,
      'initialized' => SolanaTokenAccountState.initialized,
      'frozen' => SolanaTokenAccountState.frozen,
      _ => SolanaTokenAccountState.unknown,
    };
  }

  static String? _optionalString(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  static SolAddress _address(String value, {required String field}) {
    try {
      return SolAddress(value.trim());
    } catch (_) {
      throw WalletValidationException(
        field: field,
        message: 'Invalid Solana $field address.',
      );
    }
  }

  static int _confirmationRank(String? value) => switch (value) {
    'processed' => SolanaConfirmationLevel.processed.index,
    'confirmed' => SolanaConfirmationLevel.confirmed.index,
    'finalized' => SolanaConfirmationLevel.finalized.index,
    _ => -1,
  };
}

enum SolanaConfirmationLevel { processed, confirmed, finalized }

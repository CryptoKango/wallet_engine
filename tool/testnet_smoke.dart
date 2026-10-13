import 'dart:io';

import 'package:wallet_engine/wallet_engine.dart';

/// Read-only public testnet smoke check.
///
/// This is intentionally separate from deterministic CI. Public nodes are
/// shared, rate-limited infrastructure and can be temporarily unavailable.
Future<void> main() async {
  final engine = WalletEngine(
    config: WalletEngineTestnetPreset.create(revision: 1),
    adapters: walletEngineDefaultAdapters(),
    transport: DioRpcTransport(),
  );
  try {
    final evm = engine.sessionAs<EvmChainSession>(
      WalletEngineTestnetPreset.ethereumSepoliaKey,
    );
    final solana = engine.sessionAs<SolanaChainSession>(
      WalletEngineTestnetPreset.solanaDevnetKey,
    );
    final tron = engine.sessionAs<TronChainSession>(
      WalletEngineTestnetPreset.tronNileKey,
    );
    final bitcoin = engine.sessionAs<BitcoinChainSession>(
      WalletEngineTestnetPreset.bitcoinTestnetKey,
    );

    final results = await Future.wait<_SmokeResult>(<Future<_SmokeResult>>[
      _check('ethereum.identity', evm.verifyNetworkIdentity),
      _check('ethereum.block', evm.getBlockNumber),
      _check('solana.blockhash', solana.getLatestBlockhash),
      _check('tron.block', () async => (await tron.getBlockHeader()).number),
      _check('bitcoin.identity', bitcoin.verifyNetworkIdentity),
      _check('bitcoin.genesis', bitcoin.getGenesisHash),
    ]);
    for (final result in results) {
      stdout.writeln(result.line);
    }
    final failures = results.where((result) => !result.success).length;
    if (failures > 0) {
      stderr.writeln('wallet_engine smoke failed: $failures check(s) failed.');
      exitCode = 1;
    } else {
      stdout.writeln('wallet_engine smoke passed.');
    }
  } finally {
    await engine.close();
  }
}

Future<_SmokeResult> _check(
  String name,
  Future<Object?> Function() operation,
) async {
  try {
    final value = await operation();
    return _SmokeResult(name: name, success: true, detail: value.toString());
  } on WalletError catch (error) {
    return _SmokeResult(
      name: name,
      success: false,
      detail: error.toDiagnosticMap().toString(),
    );
  } catch (error) {
    return _SmokeResult(
      name: name,
      success: false,
      detail: error.runtimeType.toString(),
    );
  }
}

final class _SmokeResult {
  const _SmokeResult({
    required this.name,
    required this.success,
    required this.detail,
  });

  final String name;
  final bool success;
  final String detail;

  String get line => '${success ? 'PASS' : 'FAIL'} $name $detail';
}

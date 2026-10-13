import '../account/wallet_account.dart';
import '../account/wallet_account_service.dart';
import '../chain/chain_adapter.dart';
import '../chain/chain_network_identity.dart';
import '../chain/chain_session.dart';
import '../config/chain_family.dart';
import '../config/wallet_chain_config.dart';
import '../config/wallet_engine_config.dart';
import '../error/wallet_error.dart';
import '../logging/wallet_logger.dart';
import '../rpc/rpc_client.dart';
import '../rpc/rpc_log_event.dart';
import '../rpc/rpc_transport.dart';
import 'wallet_engine_exception.dart';

/// Configuration-driven registry and lifecycle owner for chain sessions.
final class WalletEngine {
  factory WalletEngine({
    required WalletEngineConfig config,
    required Iterable<ChainAdapter> adapters,
    required RpcTransport transport,
    RpcLogSink? logSink,
    WalletLogger? logger,
    DateTime Function()? clock,
    bool closeTransportOnClose = true,
    WalletAccountService? walletAccounts,
  }) {
    final resolvedClock = clock ?? DateTime.now;
    final resolvedLogger = logger ?? WalletLogger.disabled();
    config.ensureUsableAt(resolvedClock());
    final engine = WalletEngine._(
      config,
      _indexAdapters(adapters),
      transport,
      logSink,
      resolvedLogger,
      resolvedClock,
      closeTransportOnClose,
      walletAccounts,
    );
    resolvedLogger.log(
      level: WalletLogLevel.info,
      category: WalletLogCategory.lifecycle,
      operation: 'engine.create',
      message: 'Wallet engine created.',
      context: <String, Object?>{
        'configRevision': config.revision,
        'configVersion': config.version,
        'chainCount': config.chains.length,
      },
    );
    return engine;
  }

  WalletEngine._(
    this._config,
    this._adapters,
    this._transport,
    this._logSink,
    this._logger,
    this._clock,
    this._closeTransportOnClose,
    this._walletAccounts,
  );

  WalletEngineConfig _config;
  final Map<ChainFamily, ChainAdapter> _adapters;
  final RpcTransport _transport;
  final RpcLogSink? _logSink;
  final WalletLogger _logger;
  final DateTime Function() _clock;
  final bool _closeTransportOnClose;
  final WalletAccountService? _walletAccounts;
  final Map<String, ChainSession> _sessions = <String, ChainSession>{};
  bool _closed = false;
  bool _updatingConfig = false;

  WalletEngineConfig get config => _config;

  /// Stateless BIP-39 and HD account API used by this engine.
  WalletAccountService get walletAccounts {
    final accounts = _walletAccounts;
    if (accounts == null) {
      throw const WalletEngineException(
        code: WalletEngineErrorCode.accountServiceUnavailable,
        message: 'Wallet account APIs require an injected account service.',
      );
    }
    return accounts;
  }

  /// Creates a 12-word BIP-39 wallet for a configured [chainKey].
  Future<CreatedWallet> createWallet12({
    required String chainKey,
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    final chain = _configuredChain(chainKey);
    return _runAccountOperation<CreatedWallet>(
      operation: 'account.create12',
      chainKey: chainKey,
      action: () => walletAccounts.createWallet12(
        family: chain.family,
        network: chain.network,
        account: account,
        passphrase: passphrase,
        exposePrivateKey: exposePrivateKey,
      ),
    );
  }

  /// Creates a 24-word BIP-39 wallet for a configured [chainKey].
  Future<CreatedWallet> createWallet24({
    required String chainKey,
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    final chain = _configuredChain(chainKey);
    return _runAccountOperation<CreatedWallet>(
      operation: 'account.create24',
      chainKey: chainKey,
      action: () => walletAccounts.createWallet24(
        family: chain.family,
        network: chain.network,
        account: account,
        passphrase: passphrase,
        exposePrivateKey: exposePrivateKey,
      ),
    );
  }

  /// Restores one account without retaining or returning the mnemonic.
  Future<WalletAccount> deriveAccount({
    required String chainKey,
    required String mnemonic,
    int account = 0,
    String passphrase = '',
    bool exposePrivateKey = false,
  }) {
    final chain = _configuredChain(chainKey);
    return _runAccountOperation<WalletAccount>(
      operation: 'account.derive',
      chainKey: chainKey,
      action: () => walletAccounts.deriveAccount(
        mnemonic: mnemonic,
        family: chain.family,
        network: chain.network,
        account: account,
        passphrase: passphrase,
        exposePrivateKey: exposePrivateKey,
      ),
    );
  }

  /// Imports a private key for a configured chain.
  Future<WalletAccount> importPrivateKey({
    required String chainKey,
    required String privateKey,
    bool exposePrivateKey = false,
  }) {
    final chain = _configuredChain(chainKey);
    return _runAccountOperation<WalletAccount>(
      operation: 'account.import',
      chainKey: chainKey,
      action: () => walletAccounts.importPrivateKey(
        privateKey: privateKey,
        family: chain.family,
        network: chain.network,
        exposePrivateKey: exposePrivateKey,
      ),
    );
  }

  /// Creates a validated address-only account for a configured chain.
  WatchOnlyWallet createWatchOnly({
    required String chainKey,
    required String address,
  }) {
    final chain = _configuredChain(chainKey);
    return walletAccounts.createWatchOnly(
      address: address,
      family: chain.family,
      network: chain.network,
    );
  }

  /// Validates a 12- or 24-word English BIP-39 mnemonic.
  bool validateMnemonic(String mnemonic) {
    _ensureReady();
    return walletAccounts.validateMnemonic(mnemonic);
  }

  /// Validates an address against the configured chain and network.
  bool validateAddress({required String chainKey, required String address}) {
    final chain = _configuredChain(chainKey);
    return walletAccounts.validateAddress(
      address: address,
      family: chain.family,
      network: chain.network,
    );
  }

  /// Validates an accepted private-key export for the configured chain.
  bool validatePrivateKey({
    required String chainKey,
    required String privateKey,
  }) {
    final chain = _configuredChain(chainKey);
    return walletAccounts.validatePrivateKey(
      privateKey: privateKey,
      family: chain.family,
    );
  }

  /// Returns the process-local session for [chainKey].
  ChainSession session(String chainKey) {
    _ensureReady();

    final chain = _config.chains[chainKey];
    if (chain == null) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.chainNotConfigured,
        message: 'Chain "$chainKey" is not configured.',
      );
    }

    final adapter = _adapters[chain.family];
    if (adapter == null) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.adapterNotRegistered,
        message: 'No adapter is registered for ${chain.family.name}.',
      );
    }

    final existing = _sessions[chainKey];
    if (existing != null) {
      _logger.log(
        level: WalletLogLevel.debug,
        category: WalletLogCategory.session,
        operation: 'session.reuse',
        message: 'Reusing an existing chain session.',
        chainKey: chainKey,
      );
      return existing;
    }

    final stopwatch = Stopwatch()..start();
    _logger.log(
      level: WalletLogLevel.debug,
      category: WalletLogCategory.session,
      operation: 'session.open',
      message: 'Opening a chain session.',
      chainKey: chainKey,
      context: <String, Object?>{
        'family': chain.family.name,
        'network': chain.network,
      },
    );
    try {
      final opened = adapter.open(
        config: chain,
        rpc: RpcClient(
          chainKey: chain.key,
          poolConfig: chain.rpcPool,
          retryConfig: _config.retry,
          transportConfig: _config.transport,
          loggingConfig: _config.rpcLogging,
          transport: _transport,
          logSink: _recordRpc,
        ),
      );
      _sessions[chainKey] = opened;
      _logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.session,
        operation: 'session.open',
        message: 'Chain session opened.',
        chainKey: chainKey,
        duration: stopwatch.elapsed,
      );
      return opened;
    } catch (error) {
      final diagnosticError = WalletErrorNormalizer.normalize(
        error,
        operation: 'session.open',
        chainKey: chainKey,
      );
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.session,
        operation: 'session.open',
        message: 'Chain session could not be opened.',
        chainKey: chainKey,
        duration: stopwatch.elapsed,
        error: diagnosticError,
      );
      rethrow;
    }
  }

  /// Returns a typed session or throws when the registered adapter exposes an
  /// unexpected session implementation.
  T sessionAs<T extends ChainSession>(String chainKey) {
    final value = session(chainKey);
    if (value is! T) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.sessionTypeMismatch,
        message: 'Chain "$chainKey" does not expose a $T session.',
      );
    }
    return value;
  }

  /// Replaces configuration after every existing session closes successfully.
  ///
  /// Fetching, signature verification, expiry policy, and durable caching of
  /// snapshots remain responsibilities of the host application. If closing an
  /// old session fails, the previous configuration remains active and future
  /// calls reopen fresh sessions from that snapshot.
  Future<void> applyConfig(WalletEngineConfig next) async {
    _ensureReady();
    next.ensureUsableAt(_clock());
    final stopwatch = Stopwatch()..start();
    _logger.log(
      level: WalletLogLevel.info,
      category: WalletLogCategory.configuration,
      operation: 'config.apply',
      message: 'Applying a wallet engine configuration.',
      context: <String, Object?>{
        'currentRevision': _config.revision,
        'requestedRevision': next.revision,
        'requestedVersion': next.version,
      },
    );
    if (next.revision < _config.revision) {
      final error = WalletEngineException(
        code: WalletEngineErrorCode.configurationRollback,
        message:
            'Configuration revision ${next.revision} is older than '
            '${_config.revision}.',
      );
      _logger.log(
        level: WalletLogLevel.warning,
        category: WalletLogCategory.configuration,
        operation: 'config.apply',
        message: 'Configuration rollback was rejected.',
        duration: stopwatch.elapsed,
        error: error,
      );
      throw error;
    }

    _updatingConfig = true;
    final previousSessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    try {
      await Future.wait(previousSessions.map((session) => session.close()));
      _config = next;
      _logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.configuration,
        operation: 'config.apply',
        message: 'Wallet engine configuration applied.',
        duration: stopwatch.elapsed,
        context: <String, Object?>{'revision': next.revision},
      );
    } catch (error, stackTrace) {
      final normalized = WalletEngineException(
        code: WalletEngineErrorCode.configurationUpdateFailed,
        message: 'Wallet engine configuration update failed.',
        cause: error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'currentRevision': _config.revision,
          'requestedRevision': next.revision,
        },
      );
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.configuration,
        operation: 'config.apply',
        message: 'Wallet engine configuration update failed.',
        duration: stopwatch.elapsed,
        error: normalized,
      );
      Error.throwWithStackTrace(normalized, stackTrace);
    } finally {
      _updatingConfig = false;
    }
  }

  /// Verifies configured network identifiers against connected nodes.
  ///
  /// Only sessions implementing [ChainNetworkIdentityVerifier] participate.
  /// When [requireAll] is true, an unsupported configured chain fails fast.
  Future<Map<String, ChainNetworkIdentity>> verifyNetworkIdentities({
    Iterable<String>? chainKeys,
    bool requireAll = false,
  }) async {
    _ensureReady();
    final stopwatch = Stopwatch()..start();
    final keys =
        chainKeys?.toList(growable: false) ??
        _config.chains.keys.toList(growable: false);
    _logger.log(
      level: WalletLogLevel.info,
      category: WalletLogCategory.configuration,
      operation: 'network.verify',
      message: 'Verifying configured network identities.',
      context: <String, Object?>{
        'chainCount': keys.length,
        'requireAll': requireAll,
      },
    );
    final result = <String, ChainNetworkIdentity>{};
    for (final key in keys) {
      final chain = _config.chains[key];
      if (chain == null) {
        // Reuse the regular public error for unknown requested keys.
        session(key);
      }
      if (chain?.chainId == null) {
        if (requireAll) {
          throw WalletEngineException(
            code: WalletEngineErrorCode.networkVerificationUnsupported,
            message: 'Network identity is not configured for "$key".',
          );
        }
        continue;
      }
      final current = session(key);
      if (current is! ChainNetworkIdentityVerifier) {
        if (requireAll) {
          throw WalletEngineException(
            code: WalletEngineErrorCode.networkVerificationUnsupported,
            message: 'Network identity verification is unavailable for "$key".',
          );
        }
        continue;
      }
      final verifier = current as ChainNetworkIdentityVerifier;
      result[key] = await verifier.verifyNetworkIdentity();
    }
    _logger.log(
      level: WalletLogLevel.info,
      category: WalletLogCategory.configuration,
      operation: 'network.verify',
      message: 'Configured network identities verified.',
      duration: stopwatch.elapsed,
      context: <String, Object?>{'verifiedChainCount': result.length},
    );
    return Map<String, ChainNetworkIdentity>.unmodifiable(result);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final stopwatch = Stopwatch()..start();
    _logger.log(
      level: WalletLogLevel.debug,
      category: WalletLogCategory.lifecycle,
      operation: 'engine.close',
      message: 'Closing wallet engine resources.',
      context: <String, Object?>{'sessionCount': _sessions.length},
    );
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    try {
      try {
        await Future.wait(sessions.map((session) => session.close()));
      } finally {
        final transport = _transport;
        if (_closeTransportOnClose && transport is ClosableRpcTransport) {
          await (transport as ClosableRpcTransport).close();
        }
      }
      _logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.lifecycle,
        operation: 'engine.close',
        message: 'Wallet engine closed.',
        duration: stopwatch.elapsed,
      );
    } catch (error) {
      final diagnosticError = WalletErrorNormalizer.normalize(
        error,
        operation: 'engine.close',
      );
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.lifecycle,
        operation: 'engine.close',
        message: 'Wallet engine close failed.',
        duration: stopwatch.elapsed,
        error: diagnosticError,
      );
      rethrow;
    }
  }

  void _recordRpc(RpcLogEvent event) {
    try {
      _logSink?.call(event);
    } catch (_) {
      // Preserve compatibility without allowing a legacy sink to break RPC.
    }
    _logger.recordRpc(event);
  }

  Future<T> _runAccountOperation<T>({
    required String operation,
    required String chainKey,
    required Future<T> Function() action,
  }) async {
    final stopwatch = Stopwatch()..start();
    _logger.log(
      level: WalletLogLevel.debug,
      category: WalletLogCategory.account,
      operation: operation,
      message: 'Wallet account operation started.',
      chainKey: chainKey,
    );
    try {
      final result = await action();
      _logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.account,
        operation: operation,
        message: 'Wallet account operation completed.',
        chainKey: chainKey,
        duration: stopwatch.elapsed,
      );
      return result;
    } catch (error) {
      _logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.account,
        operation: operation,
        message: 'Wallet account operation failed.',
        chainKey: chainKey,
        duration: stopwatch.elapsed,
        error: error,
      );
      rethrow;
    }
  }

  void _ensureReady() {
    if (_closed) {
      throw const WalletEngineException(
        code: WalletEngineErrorCode.engineClosed,
        message: 'Wallet engine is closed.',
      );
    }
    if (_updatingConfig) {
      throw const WalletEngineException(
        code: WalletEngineErrorCode.configurationUpdateInProgress,
        message: 'Wallet engine configuration is being updated.',
      );
    }
  }

  WalletChainConfig _configuredChain(String chainKey) {
    _ensureReady();
    final chain = _config.chains[chainKey];
    if (chain == null) {
      throw WalletEngineException(
        code: WalletEngineErrorCode.chainNotConfigured,
        message: 'Chain "$chainKey" is not configured.',
      );
    }
    return chain;
  }

  static Map<ChainFamily, ChainAdapter> _indexAdapters(
    Iterable<ChainAdapter> adapters,
  ) {
    final indexed = <ChainFamily, ChainAdapter>{};
    for (final adapter in adapters) {
      if (indexed.containsKey(adapter.family)) {
        throw WalletEngineException(
          code: WalletEngineErrorCode.duplicateAdapter,
          message: 'Duplicate adapter for ${adapter.family.name}.',
        );
      }
      indexed[adapter.family] = adapter;
    }
    return Map<ChainFamily, ChainAdapter>.unmodifiable(indexed);
  }
}

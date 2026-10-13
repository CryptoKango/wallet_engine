import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletError', () {
    test('public error catalog is unique and protocol-versioned', () {
      const expectedCodes = <String>[
        'engine.chainNotConfigured',
        'engine.adapterNotRegistered',
        'engine.duplicateAdapter',
        'engine.configurationRollback',
        'engine.configurationUpdateInProgress',
        'engine.configurationUpdateFailed',
        'engine.engineClosed',
        'engine.sessionTypeMismatch',
        'validation.invalidArgument',
        'rpc.transport.timeout',
        'rpc.transport.connection',
        'rpc.transport.invalidResponse',
        'rpc.transport.httpStatus',
        'rpc.transport.cancelled',
        'rpc.transport.unknown',
        'rpc.jsonRpc.invalidResponse',
        'rpc.jsonRpc.serverError',
        'signing.invalidPrivateKey',
        'signing.invalidTransaction',
        'signing.nativeRuntimeUnavailable',
        'signing.signingFailed',
        'chain.bitcoin.electrum',
        'chain.tron.rpc',
        'internal.invalidState',
        'internal.unknown',
        'signing.runtimeNotInitialized',
        'configuration.expired',
        'configuration.schemaUnsupported',
        'configuration.networkMismatch',
        'configuration.networkVerificationUnsupported',
        'transaction.confirmationTimeout',
        'transaction.confirmationCancelled',
        'chain.sui.insufficientGas',
        'chain.sui.insufficientBalance',
        'chain.sui.invalidTransaction',
        'chain.sui.objectVersionConflict',
        'chain.sui.rpc',
        'account.invalidMnemonic',
        'account.invalidAddress',
        'account.invalidPrivateKey',
        'account.unsupportedChain',
        'account.generationFailed',
        'account.derivationFailed',
        'signing.nativeVersionMismatch',
        'signing.nativeSelfTestFailed',
        'engine.accountServiceUnavailable',
      ];

      final actualCodes = WalletErrorCode.values
          .map((code) => code.value)
          .toList(growable: false);

      expect(WalletErrorProtocol.version, 1);
      expect(actualCodes, expectedCodes);
      expect(actualCodes.toSet(), hasLength(actualCodes.length));
      for (final code in WalletErrorCode.values) {
        expect(WalletErrorProtocol.tryParse(code.value), code);
      }
      expect(WalletErrorProtocol.tryParse('future.newCode'), isNull);
    });

    test('all specialized errors expose the common contract', () {
      const errors = <WalletError>[
        WalletEngineException(
          code: WalletEngineErrorCode.engineClosed,
          message: 'closed',
        ),
        RpcTransportException(
          failure: RpcTransportFailure.timeout,
          message: 'timeout',
          retryable: true,
        ),
        JsonRpcException(
          code: -32602,
          message: 'invalid params',
          retryable: false,
        ),
        WalletSigningException(
          code: WalletSigningErrorCode.signingFailed,
          message: 'failed',
        ),
        ElectrumException('failed'),
        TronRpcException('failed'),
        WalletAccountException(
          code: WalletAccountErrorCode.invalidMnemonic,
          message: 'invalid mnemonic',
        ),
      ];

      expect(errors.map((error) => error.errorCode), <String>[
        'engine.engineClosed',
        'rpc.transport.timeout',
        'rpc.jsonRpc.serverError',
        'signing.signingFailed',
        'chain.bitcoin.electrum',
        'chain.tron.rpc',
        'account.invalidMnemonic',
      ]);
    });

    test('normalizes dependency errors and preserves the cause privately', () {
      final cause = StateError('dependency detail');
      final error = WalletErrorNormalizer.normalize(
        cause,
        operation: 'eth_call',
        chainKey: 'ethereum',
      );

      expect(error.errorCode, 'internal.invalidState');
      expect(error.retryable, isFalse);
      expect(error.cause, same(cause));
      expect(error.context, <String, Object?>{
        'operation': 'eth_call',
        'chainKey': 'ethereum',
      });
      expect(error.toDiagnosticMap().toString(), isNot(contains('dependency')));
    });

    test('guard exposes only normalized errors', () async {
      await expectLater(
        WalletErrorNormalizer.guard<void>(
          () async => throw FormatException('secret payload'),
          operation: 'decode',
        ),
        throwsA(
          isA<NormalizedWalletException>().having(
            (error) => error.message,
            'message',
            'Invalid wallet engine input.',
          ),
        ),
      );
    });

    test('diagnostic output omits causes and stack traces', () {
      const error = RpcTransportException(
        failure: RpcTransportFailure.httpStatus,
        message: 'RPC endpoint returned HTTP 429.',
        retryable: true,
        statusCode: 429,
        cause: 'credential=secret',
        context: <String, Object?>{'operation': 'eth_call'},
      );

      expect(error.toDiagnosticMap(), <String, Object?>{
        'codeVersion': 1,
        'category': 'transport',
        'code': 'rpc.transport.httpStatus',
        'message': 'RPC endpoint returned HTTP 429.',
        'retryable': true,
        'context': <String, Object?>{'operation': 'eth_call'},
      });
      expect(error.toString(), isNot(contains('secret')));
    });

    test('Electrum server errors retain raw text only as a cause', () {
      final error = ElectrumException.fromServer(
        'No such mempool or blockchain transaction: secret-hash',
      );

      expect(error.transactionNotFound, isTrue);
      expect(error.cause, contains('secret-hash'));
      expect(error.toString(), isNot(contains('secret-hash')));
      expect(
        error.toDiagnosticMap().toString(),
        isNot(contains('secret-hash')),
      );
    });
  });
}

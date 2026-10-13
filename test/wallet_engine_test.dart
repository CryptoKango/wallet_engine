import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletEngine', () {
    test(
      'emits structured lifecycle, session, and configuration logs',
      () async {
        final events = <WalletLogEvent>[];
        final logger = WalletLogger(
          sink: events.add,
          minimumLevel: WalletLogLevel.debug,
        );
        final engine = WalletEngine(
          config: _config(revision: 1),
          adapters: <ChainAdapter>[_FakeAdapter()],
          transport: _FakeTransport(),
          logger: logger,
        );

        engine.session('ethereum');
        engine.session('ethereum');
        await engine.applyConfig(_config(revision: 2));
        await engine.close();

        expect(
          events.map((event) => event.operation),
          containsAll(<String>[
            'engine.create',
            'session.open',
            'session.reuse',
            'config.apply',
            'engine.close',
          ]),
        );
        expect(events.every((event) => event.message.isNotEmpty), isTrue);
      },
    );

    test('opens and reuses a chain session', () async {
      final adapter = _FakeAdapter();
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[adapter],
        transport: _FakeTransport(),
      );

      final first = engine.session('ethereum');
      final second = engine.session('ethereum');

      expect(identical(first, second), isTrue);
      expect(adapter.openCount, 1);
      await engine.close();
    });

    test('rejects configuration rollback', () async {
      final engine = WalletEngine(
        config: _config(revision: 2),
        adapters: <ChainAdapter>[_FakeAdapter()],
        transport: _FakeTransport(),
      );

      await expectLater(
        engine.applyConfig(_config(revision: 1)),
        throwsA(
          isA<WalletEngineException>().having(
            (error) => error.code,
            'code',
            WalletEngineErrorCode.configurationRollback,
          ),
        ),
      );
      await engine.close();
    });

    test('closes old sessions when configuration changes', () async {
      final adapter = _FakeAdapter();
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[adapter],
        transport: _FakeTransport(),
      );
      final oldSession = engine.session('ethereum') as _FakeSession;

      await engine.applyConfig(_config(revision: 2));

      expect(oldSession.closed, isTrue);
      expect(identical(oldSession, engine.session('ethereum')), isFalse);
      await engine.close();
    });

    test('does not expose new sessions during configuration update', () async {
      final closeGate = Completer<void>();
      final adapter = _FakeAdapter(closeGate: closeGate.future);
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[adapter],
        transport: _FakeTransport(),
      );
      engine.session('ethereum');

      final update = engine.applyConfig(_config(revision: 2));

      expect(engine.config.revision, 1);
      expect(
        () => engine.session('ethereum'),
        throwsA(
          isA<WalletEngineException>().having(
            (error) => error.code,
            'code',
            WalletEngineErrorCode.configurationUpdateInProgress,
          ),
        ),
      );

      closeGate.complete();
      await update;
      expect(engine.config.revision, 2);
      await engine.close();
    });

    test(
      'keeps the previous snapshot when closing an old session fails',
      () async {
        final adapter = _FakeAdapter(closeError: StateError('close failed'));
        final engine = WalletEngine(
          config: _config(revision: 1),
          adapters: <ChainAdapter>[adapter],
          transport: _FakeTransport(),
        );
        engine.session('ethereum');

        await expectLater(
          engine.applyConfig(_config(revision: 2)),
          throwsA(
            isA<WalletEngineException>()
                .having(
                  (error) => error.publicCode,
                  'publicCode',
                  WalletErrorCode.engineConfigurationUpdateFailed,
                )
                .having(
                  (error) => error.context['currentRevision'],
                  'currentRevision',
                  1,
                ),
          ),
        );

        expect(engine.config.revision, 1);
        expect(engine.session('ethereum').config.network, 'mainnet');
        await engine.close();
      },
    );

    test('closes an owned lifecycle transport exactly once', () async {
      final transport = _LifecycleTransport();
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[_FakeAdapter()],
        transport: transport,
      );

      await engine.close();
      await engine.close();

      expect(transport.closeCount, 1);
    });

    test('can use an externally owned lifecycle transport', () async {
      final transport = _LifecycleTransport();
      final engine = WalletEngine(
        config: _config(revision: 1),
        adapters: <ChainAdapter>[_FakeAdapter()],
        transport: transport,
        closeTransportOnClose: false,
      );

      await engine.close();

      expect(transport.closeCount, 0);
    });
  });
}

WalletEngineConfig _config({required int revision}) {
  return WalletEngineConfig(
    revision: revision,
    version: 'test-$revision',
    chains: <WalletChainConfig>[
      WalletChainConfig(
        key: 'ethereum',
        family: ChainFamily.evm,
        network: 'mainnet',
        chainId: '1',
        nativeSymbol: 'ETH',
        nativeDecimals: 18,
        rpcPool: RpcPoolConfig(
          endpoints: <RpcEndpoint>[
            RpcEndpoint.parse('https://rpc.example.com'),
          ],
        ),
      ),
    ],
  );
}

final class _FakeAdapter implements ChainAdapter {
  _FakeAdapter({this.closeGate, this.closeError});

  final Future<void>? closeGate;
  Object? closeError;
  int openCount = 0;

  @override
  ChainFamily get family => ChainFamily.evm;

  @override
  ChainSession open({
    required WalletChainConfig config,
    required RpcClient rpc,
  }) {
    openCount++;
    final error = closeError;
    closeError = null;
    return _FakeSession(config, closeGate: closeGate, closeError: error);
  }
}

final class _FakeTransport implements RpcTransport {
  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    return RpcResponse(statusCode: 200, data: const <String, Object?>{});
  }
}

final class _LifecycleTransport implements RpcTransport, ClosableRpcTransport {
  int closeCount = 0;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<RpcResponse> send({
    required RpcEndpoint endpoint,
    required RpcRequest request,
    required RpcTransportConfig config,
  }) async {
    return RpcResponse(statusCode: 200, data: const <String, Object?>{});
  }
}

final class _FakeSession implements ChainSession {
  _FakeSession(this.config, {this.closeGate, this.closeError});

  @override
  final WalletChainConfig config;

  bool closed = false;
  final Future<void>? closeGate;
  final Object? closeError;

  @override
  Future<void> close() async {
    await closeGate;
    if (closeError case final error?) throw error;
    closed = true;
  }
}

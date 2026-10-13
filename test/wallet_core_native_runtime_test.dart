import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  const expected = WalletCoreBridgeManifest(
    abiVersion: 7,
    upstreamVersion: '1.2.3',
    upstreamCommit: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    sourceRepository: 'https://example.invalid/wallet-core.git',
    license: 'Apache-2.0',
  );
  const matchingInfo = WalletCoreNativeBridgeInfo(
    abiVersion: 7,
    upstreamVersion: '1.2.3',
    upstreamCommit: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );

  test('coalesces concurrent startup initialization', () async {
    final bridge = _FakeBridge(matchingInfo);
    final events = <WalletLogEvent>[];
    final runtime = WalletCoreNativeRuntime(
      bridge: bridge,
      manifest: expected,
      logger: WalletLogger(
        sink: events.add,
        minimumLevel: WalletLogLevel.debug,
      ),
    );

    final results = await Future.wait(<Future<WalletCoreNativeBridgeInfo>>[
      runtime.initialize(),
      runtime.initialize(),
      runtime.initialize(),
    ]);

    expect(results, everyElement(same(matchingInfo)));
    expect(bridge.loadCount, 1);
    expect(bridge.selfTestCount, 1);
    expect(runtime.state, WalletCoreNativeRuntimeState.ready);
    expect(runtime.info, same(matchingInfo));
    expect(runtime.ensureInitialized, returnsNormally);
    expect(
      events.where((event) => event.operation == 'native.initialize'),
      isNotEmpty,
    );
    expect(
      events.any(
        (event) =>
            event.message == 'Wallet Core native runtime initialized.' &&
            event.context['selfTest'] == 'passed',
      ),
      isTrue,
    );
  });

  test('rejects an artifact with different provenance metadata', () async {
    final runtime = WalletCoreNativeRuntime(
      bridge: _FakeBridge(
        const WalletCoreNativeBridgeInfo(
          abiVersion: 8,
          upstreamVersion: '1.2.4',
          upstreamCommit: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      ),
      manifest: expected,
    );

    await expectLater(
      runtime.initialize(),
      throwsA(
        isA<WalletSigningException>()
            .having(
              (error) => error.code,
              'code',
              WalletSigningErrorCode.nativeVersionMismatch,
            )
            .having(
              (error) => error.publicCode,
              'publicCode',
              WalletErrorCode.signingNativeVersionMismatch,
            ),
      ),
    );
    expect(runtime.state, WalletCoreNativeRuntimeState.failed);
    expect(runtime.ensureInitialized, throwsA(same(runtime.failure)));
  });

  test('normalizes native known-answer test failures', () async {
    final runtime = WalletCoreNativeRuntime(
      bridge: _FakeBridge(matchingInfo, selfTestError: StateError('bad hash')),
      manifest: expected,
    );

    await expectLater(
      runtime.initialize(),
      throwsA(
        isA<WalletSigningException>().having(
          (error) => error.code,
          'code',
          WalletSigningErrorCode.nativeSelfTestFailed,
        ),
      ),
    );
    expect(runtime.state, WalletCoreNativeRuntimeState.failed);
  });

  test('requires startup initialization', () {
    final runtime = WalletCoreNativeRuntime(
      bridge: _FakeBridge(matchingInfo),
      manifest: expected,
    );

    expect(
      runtime.ensureInitialized,
      throwsA(
        isA<WalletSigningException>().having(
          (error) => error.code,
          'code',
          WalletSigningErrorCode.runtimeNotInitialized,
        ),
      ),
    );
  });
}

final class _FakeBridge implements WalletCoreNativeBridge {
  _FakeBridge(this.info, {this.selfTestError});

  final WalletCoreNativeBridgeInfo info;
  final Object? selfTestError;
  int loadCount = 0;
  int selfTestCount = 0;

  @override
  Future<WalletCoreNativeBridgeInfo> load() async {
    loadCount += 1;
    await Future<void>.delayed(Duration.zero);
    return info;
  }

  @override
  Future<void> selfTest() async {
    selfTestCount += 1;
    final error = selfTestError;
    if (error != null) throw error;
  }

  @override
  bool supportsJsonSigning(int coinType) => true;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) => Uint8List.fromList(<int>[1]);
}

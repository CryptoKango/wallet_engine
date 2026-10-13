import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

const _mnemonic = 'test test test test test test test test test test test junk';

void main() {
  test(
    'derives through the initialized owned bridge and wipes key bytes',
    () async {
      final bridge = _KeyBridge();
      final runtime = WalletCoreNativeRuntime(bridge: bridge);
      await runtime.initialize();
      final accounts = WalletCoreAccountService(runtime: runtime);

      final account = await accounts.deriveAccount(
        mnemonic: _mnemonic,
        passphrase: 'passphrase',
        family: ChainFamily.evm,
        account: 2,
        exposePrivateKey: true,
      );

      expect(account.derivationPath, "m/44'/60'/0'/0/2");
      expect(account.address, '0x0000000000000000000000000000000000000001');
      expect(account.privateKey, '01' * 32);
      expect(bridge.lastCoinType, 60);
      expect(bridge.lastPath, "m/44'/60'/0'/0/2");
      expect(bridge.lastPassphrase, 'passphrase');
      expect(
        bridge.lastPublicKeyMode,
        WalletCorePublicKeyMode.secp256k1Compressed,
      );
      expect(bridge.returnedPrivateKey, everyElement(0));
    },
  );

  test(
    'imports through owned key inspection and wipes returned key bytes',
    () async {
      final bridge = _KeyBridge();
      final runtime = WalletCoreNativeRuntime(bridge: bridge);
      await runtime.initialize();
      final accounts = WalletCoreAccountService(runtime: runtime);

      final account = await accounts.importPrivateKey(
        privateKey: '01' * 32,
        family: ChainFamily.evm,
        exposePrivateKey: true,
      );

      expect(account.source, WalletAccountSource.privateKey);
      expect(account.privateKey, '01' * 32);
      expect(bridge.inspectedPrivateKey, everyElement(0));
      expect(bridge.returnedPrivateKey, everyElement(0));
    },
  );
}

final class _KeyBridge
    implements WalletCoreNativeBridge, WalletCoreKeyDerivationBridge {
  int? lastCoinType;
  String? lastPath;
  String? lastPassphrase;
  WalletCorePublicKeyMode? lastPublicKeyMode;
  Uint8List? returnedPrivateKey;
  Uint8List? inspectedPrivateKey;

  @override
  Future<WalletCoreNativeBridgeInfo> load() async =>
      const WalletCoreNativeBridgeInfo(
        abiVersion: 2,
        upstreamVersion: '4.8.4',
        upstreamCommit: 'd40d24a63d92619167903369308bf0e2f7eb3a59',
      );

  @override
  Future<void> selfTest() async {}

  @override
  bool supportsJsonSigning(int coinType) => false;

  @override
  Uint8List signJson({
    required int coinType,
    required String json,
    required Uint8List privateKey,
  }) => throw UnsupportedError('not used');

  @override
  WalletCoreKeyInfo deriveKey({
    required int coinType,
    required String mnemonic,
    required String passphrase,
    required String derivationPath,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    lastCoinType = coinType;
    lastPath = derivationPath;
    lastPassphrase = passphrase;
    lastPublicKeyMode = publicKeyMode;
    return _keyInfo();
  }

  @override
  WalletCoreKeyInfo inspectKey({
    required int coinType,
    required Uint8List privateKey,
    required WalletCorePublicKeyMode publicKeyMode,
  }) {
    inspectedPrivateKey = privateKey;
    return _keyInfo();
  }

  WalletCoreKeyInfo _keyInfo() {
    final privateKey = Uint8List.fromList(List<int>.filled(32, 1));
    returnedPrivateKey = privateKey;
    return WalletCoreKeyInfo(
      privateKey: privateKey,
      publicKey: Uint8List.fromList(<int>[2, ...List<int>.filled(32, 3)]),
      address: '0x0000000000000000000000000000000000000001',
    );
  }
}

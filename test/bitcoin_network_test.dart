import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('BitcoinNetwork', () {
    test('uses canonical BIP-84 mainnet paths', () {
      final network = BitcoinNetwork.parse('mainnet');

      expect(network.hrp, 'bc');
      expect(network.receivePath(0), "m/84'/0'/0'/0/0");
      expect(network.changePath(7), "m/84'/0'/0'/1/7");
    });

    test('uses SLIP-44 test coin type for every non-mainnet network', () {
      for (final name in <String>['testnet', 'signet', 'regtest']) {
        final network = BitcoinNetwork.parse(name);
        expect(network.receivePath(0), "m/84'/1'/0'/0/0");
        expect(network.changePath(1), "m/84'/1'/0'/1/1");
      }
      expect(BitcoinNetwork.parse('testnet').hrp, 'tb');
      expect(BitcoinNetwork.parse('signet').hrp, 'tb');
      expect(BitcoinNetwork.parse('regtest').hrp, 'bcrt');
    });

    test('rejects unknown networks and invalid address indexes', () {
      expect(
        () => BitcoinNetwork.parse('unknown'),
        throwsA(isA<WalletValidationException>()),
      );
      expect(
        () => BitcoinNetwork.mainnet.receivePath(-1),
        throwsA(isA<WalletValidationException>()),
      );
    });
  });
}

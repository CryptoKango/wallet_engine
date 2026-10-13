import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletAddressValidator addresses', () {
    test('validates EIP-55 EVM addresses', () {
      expect(
        WalletAddressValidator.validateAddress(
          address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          family: ChainFamily.evm,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: '0x5aAEb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          family: ChainFamily.evm,
        ),
        isFalse,
      );
    });

    test('validates Solana, TRON, and Sui formats', () {
      expect(
        WalletAddressValidator.validateAddress(
          address: '11111111111111111111111111111111',
          family: ChainFamily.solana,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
          family: ChainFamily.tron,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: '0x${'0' * 64}',
          family: ChainFamily.sui,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: 'invalid',
          family: ChainFamily.solana,
        ),
        isFalse,
      );
    });

    test('enforces Bitcoin network and checksum', () {
      const mainnet = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
      const testnet = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
      expect(
        WalletAddressValidator.validateAddress(
          address: mainnet,
          family: ChainFamily.bitcoin,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: testnet,
          family: ChainFamily.bitcoin,
          network: 'testnet',
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: mainnet,
          family: ChainFamily.bitcoin,
          network: 'testnet',
        ),
        isFalse,
      );
      expect(
        WalletAddressValidator.validateAddress(
          address: '1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
          family: ChainFamily.bitcoin,
        ),
        isTrue,
      );
    });

    test('reports unsupported chain families', () {
      expect(WalletAddressValidator.supports(ChainFamily.evm), isTrue);
      expect(WalletAddressValidator.supports(ChainFamily.aptos), isFalse);
      expect(
        WalletAddressValidator.validateAddress(
          address: '0x${'0' * 64}',
          family: ChainFamily.aptos,
        ),
        isFalse,
      );
    });
  });

  group('WalletAddressValidator private keys', () {
    test('validates secp256k1 and ed25519 exports', () {
      final validHex = '${'0' * 63}1';
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: validHex,
          family: ChainFamily.evm,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: '0x$validHex',
          family: ChainFamily.bitcoin,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: '0' * 64,
          family: ChainFamily.tron,
        ),
        isFalse,
      );
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: 'a' * 64,
          family: ChainFamily.sui,
        ),
        isTrue,
      );
    });

    test('validates Solana base58 seed length', () {
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: '11111111111111111111111111111111',
          family: ChainFamily.solana,
        ),
        isTrue,
      );
      expect(
        WalletAddressValidator.validatePrivateKey(
          privateKey: '0OIl',
          family: ChainFamily.solana,
        ),
        isFalse,
      );
    });
  });
}

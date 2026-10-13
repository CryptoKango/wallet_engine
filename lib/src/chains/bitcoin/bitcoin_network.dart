import '../../error/wallet_error.dart';

/// Canonical Bitcoin network parameters used for BIP-84 derivation and
/// SegWit address encoding.
enum BitcoinNetwork {
  mainnet(coinType: 0, hrp: 'bc'),
  testnet(coinType: 1, hrp: 'tb'),
  signet(coinType: 1, hrp: 'tb'),
  regtest(coinType: 1, hrp: 'bcrt');

  const BitcoinNetwork({required this.coinType, required this.hrp});

  final int coinType;
  final String hrp;

  String receivePath(int addressIndex) =>
      _path(change: 0, addressIndex: addressIndex);

  String changePath(int addressIndex) =>
      _path(change: 1, addressIndex: addressIndex);

  String _path({required int change, required int addressIndex}) {
    if (addressIndex < 0 || addressIndex > 0x7fffffff) {
      throw const WalletValidationException(
        message: 'Bitcoin address index must be between 0 and 2147483647.',
        field: 'addressIndex',
      );
    }
    return "m/84'/$coinType'/0'/$change/$addressIndex";
  }

  static BitcoinNetwork parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'mainnet' || 'main' || 'livenet' || 'bitcoin' => mainnet,
      'testnet' || 'test' => testnet,
      'signet' => signet,
      'regtest' => regtest,
      _ => throw const WalletValidationException(
        message: 'Unsupported Bitcoin network.',
        field: 'network',
      ),
    };
  }
}

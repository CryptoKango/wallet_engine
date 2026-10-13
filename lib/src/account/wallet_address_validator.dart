import 'package:blockchain_utils/blockchain_utils.dart'
    show
        Base58Decoder,
        Ed25519PublicKey,
        QuickCrypto,
        Secp256k1PrivateKey,
        SegwitBech32Decoder;

import '../config/chain_family.dart';

/// Pure-Dart address and private-key format validation.
///
/// Validation is intentionally limited to chain families with production
/// adapters. It performs no RPC calls and does not retain supplied values.
abstract final class WalletAddressValidator {
  static const Set<ChainFamily> supportedFamilies = <ChainFamily>{
    ChainFamily.bitcoin,
    ChainFamily.evm,
    ChainFamily.solana,
    ChainFamily.tron,
    ChainFamily.sui,
  };

  static bool supports(ChainFamily family) {
    return supportedFamilies.contains(family);
  }

  static bool validateAddress({
    required String address,
    required ChainFamily family,
    String network = 'mainnet',
  }) {
    final value = address.trim();
    if (value.isEmpty || !supports(family)) return false;
    return switch (family) {
      ChainFamily.evm => _validEvmAddress(value),
      ChainFamily.solana => _validSolanaAddress(value),
      ChainFamily.tron => _validTronAddress(value),
      ChainFamily.bitcoin => _validBitcoinAddress(value, network),
      ChainFamily.sui => RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value),
      _ => false,
    };
  }

  static bool validatePrivateKey({
    required String privateKey,
    required ChainFamily family,
  }) {
    if (!supports(family)) return false;
    if (family == ChainFamily.solana) {
      try {
        final bytes = Base58Decoder.decode(privateKey.trim());
        return bytes.length == 32 || bytes.length == 64;
      } catch (_) {
        return false;
      }
    }
    final bytes = _tryDecodeHex(privateKey);
    if (bytes == null || bytes.length != 32) return false;
    if (family == ChainFamily.evm ||
        family == ChainFamily.tron ||
        family == ChainFamily.bitcoin) {
      return Secp256k1PrivateKey.isValidBytes(bytes);
    }
    return family == ChainFamily.sui;
  }

  static bool _validEvmAddress(String address) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) return false;
    final hex = address.substring(2);
    final hasUpper = hex.contains(RegExp(r'[A-F]'));
    final hasLower = hex.contains(RegExp(r'[a-f]'));
    if (!(hasUpper && hasLower)) return true;
    final lower = hex.toLowerCase();
    final hash = _hex(QuickCrypto.keccack256Hash(lower.codeUnits));
    final expected = StringBuffer('0x');
    for (var index = 0; index < lower.length; index += 1) {
      final uppercase = int.parse(hash[index], radix: 16) >= 8;
      final character = lower[index];
      expected.write(uppercase ? character.toUpperCase() : character);
    }
    return expected.toString() == address;
  }

  static bool _validSolanaAddress(String address) {
    try {
      final bytes = Base58Decoder.decode(address);
      if (bytes.length != 32) return false;
      Ed25519PublicKey.fromBytes(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _validTronAddress(String address) {
    try {
      if (address.length != 34 || !address.startsWith('T')) return false;
      final payload = Base58Decoder.checkDecode(address);
      return payload.length == 21 && payload.first == 0x41;
    } catch (_) {
      return false;
    }
  }

  static bool _validBitcoinAddress(String address, String network) {
    final hrp = _bitcoinHrp(network);
    if (hrp == null) return false;
    final lower = address.toLowerCase();
    if (lower.startsWith('${hrp}1')) {
      if (address != lower && address != address.toUpperCase()) return false;
      try {
        final (witnessVersion, program) = SegwitBech32Decoder.decode(
          hrp,
          lower,
        );
        if (witnessVersion == 0) {
          return program.length == 20 || program.length == 32;
        }
        return witnessVersion == 1 && program.length == 32;
      } catch (_) {
        return false;
      }
    }
    try {
      final payload = Base58Decoder.checkDecode(address);
      if (payload.length != 21) return false;
      final prefixes = switch (hrp) {
        'bc' => const <int>[0x00, 0x05],
        'tb' || 'bcrt' => const <int>[0x6f, 0xc4],
        _ => const <int>[],
      };
      return prefixes.contains(payload.first);
    } catch (_) {
      return false;
    }
  }

  static String? _bitcoinHrp(String network) {
    return switch (network.trim().toLowerCase()) {
      'mainnet' || 'main' || 'livenet' || 'bitcoin' => 'bc',
      'testnet' || 'test' || 'signet' => 'tb',
      'regtest' => 'bcrt',
      _ => null,
    };
  }

  static List<int>? _tryDecodeHex(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.startsWith('0x') || trimmed.startsWith('0X')
        ? trimmed.substring(2)
        : trimmed;
    if (normalized.length != 64 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
      return null;
    }
    return <int>[
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ];
  }

  static String _hex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

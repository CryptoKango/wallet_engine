#include "wallet_engine_wallet_core.h"

#include <TrustWalletCore/TWAnySigner.h>
#include <TrustWalletCore/TWCurve.h>
#include <TrustWalletCore/TWCoinType.h>
#include <TrustWalletCore/TWData.h>
#include <TrustWalletCore/TWEthereumMessageSigner.h>
#include <TrustWalletCore/TWHDWallet.h>
#include <TrustWalletCore/TWHash.h>
#include <TrustWalletCore/TWPrivateKey.h>
#include <TrustWalletCore/TWPublicKey.h>
#include <TrustWalletCore/TWString.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>

#ifndef WALLET_ENGINE_WALLET_CORE_VERSION
#error "WALLET_ENGINE_WALLET_CORE_VERSION must be set by the verified build"
#endif

#ifndef WALLET_ENGINE_WALLET_CORE_COMMIT
#error "WALLET_ENGINE_WALLET_CORE_COMMIT must be set by the verified build"
#endif

namespace {

constexpr uint32_t kBridgeAbiVersion = 2;
constexpr char kUpstreamVersion[] = WALLET_ENGINE_WALLET_CORE_VERSION;
constexpr char kUpstreamCommit[] = WALLET_ENGINE_WALLET_CORE_COMMIT;

constexpr std::array<uint8_t, 32> kEmptySha256 = {
    0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
    0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
    0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
    0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
};

struct DataDeleter {
  void operator()(TWData* data) const {
    if (data != nullptr) TWDataDelete(data);
  }
};

struct SensitiveDataDeleter {
  void operator()(TWData* data) const {
    if (data != nullptr) {
      TWDataReset(data);
      TWDataDelete(data);
    }
  }
};

struct StringDeleter {
  void operator()(TWString* value) const {
    if (value != nullptr) TWStringDelete(value);
  }
};

struct PrivateKeyDeleter {
  void operator()(TWPrivateKey* key) const {
    if (key != nullptr) TWPrivateKeyDelete(key);
  }
};

struct HDWalletDeleter {
  void operator()(TWHDWallet* wallet) const {
    if (wallet != nullptr) TWHDWalletDelete(wallet);
  }
};

struct PublicKeyDeleter {
  void operator()(TWPublicKey* key) const {
    if (key != nullptr) TWPublicKeyDelete(key);
  }
};

using DataPtr = std::unique_ptr<TWData, DataDeleter>;
using SensitiveDataPtr = std::unique_ptr<TWData, SensitiveDataDeleter>;
using StringPtr = std::unique_ptr<TWString, StringDeleter>;
using PrivateKeyPtr = std::unique_ptr<TWPrivateKey, PrivateKeyDeleter>;
using HDWalletPtr = std::unique_ptr<TWHDWallet, HDWalletDeleter>;
using PublicKeyPtr = std::unique_ptr<TWPublicKey, PublicKeyDeleter>;

PublicKeyPtr GetPublicKey(TWPrivateKey* key, TWCoinType coin,
                          uint32_t mode) {
  switch (mode) {
    case 0:
      return PublicKeyPtr(TWPrivateKeyGetPublicKey(key, coin));
    case 1:
      return PublicKeyPtr(TWPrivateKeyGetPublicKeySecp256k1(key, true));
    case 2:
      return PublicKeyPtr(TWPrivateKeyGetPublicKeyEd25519(key));
    default:
      return PublicKeyPtr(nullptr);
  }
}

int32_t ExportKeyInfo(TWCoinType coin, TWPrivateKey* key, uint32_t mode,
                      uint8_t* private_output, uint32_t private_capacity,
                      uint32_t* private_length, uint8_t* public_output,
                      uint32_t public_capacity, uint32_t* public_length,
                      uint8_t* address_output, uint32_t address_capacity,
                      uint32_t* address_length) {
  PublicKeyPtr public_key(GetPublicKey(key, coin, mode));
  SensitiveDataPtr private_data(TWPrivateKeyData(key));
  DataPtr public_data(public_key == nullptr ? nullptr
                                            : TWPublicKeyData(public_key.get()));
  StringPtr address(TWCoinTypeDeriveAddress(coin, key));
  if (private_data == nullptr || public_data == nullptr || address == nullptr) {
    return 4;
  }
  const size_t private_size = TWDataSize(private_data.get());
  const size_t public_size = TWDataSize(public_data.get());
  const size_t address_size = TWStringSize(address.get());
  *private_length = static_cast<uint32_t>(private_size);
  *public_length = static_cast<uint32_t>(public_size);
  *address_length = static_cast<uint32_t>(address_size);
  if (private_output == nullptr || private_capacity < private_size ||
      public_output == nullptr || public_capacity < public_size ||
      address_output == nullptr || address_capacity < address_size) {
    return 3;
  }
  std::memcpy(private_output, TWDataBytes(private_data.get()), private_size);
  std::memcpy(public_output, TWDataBytes(public_data.get()), public_size);
  std::memcpy(address_output, TWStringUTF8Bytes(address.get()), address_size);
  return address_size == 0 ? 4 : 0;
}

}  // namespace

uint32_t wallet_engine_wallet_core_abi_version(void) {
  return kBridgeAbiVersion;
}

const uint8_t* wallet_engine_wallet_core_upstream_version(void) {
  return reinterpret_cast<const uint8_t*>(kUpstreamVersion);
}

uint32_t wallet_engine_wallet_core_upstream_version_length(void) {
  return static_cast<uint32_t>(sizeof(kUpstreamVersion) - 1);
}

const uint8_t* wallet_engine_wallet_core_upstream_commit(void) {
  return reinterpret_cast<const uint8_t*>(kUpstreamCommit);
}

uint32_t wallet_engine_wallet_core_upstream_commit_length(void) {
  return static_cast<uint32_t>(sizeof(kUpstreamCommit) - 1);
}

int32_t wallet_engine_wallet_core_self_test(void) {
  const uint8_t non_null_empty_input = 0;
  DataPtr input(TWDataCreateWithBytes(&non_null_empty_input, 0));
  if (input == nullptr) {
    return 1;
  }

  DataPtr digest(TWHashSHA256(input.get()));
  if (digest == nullptr) {
    return 2;
  }

  const bool valid = TWDataSize(digest.get()) == kEmptySha256.size() &&
                     std::memcmp(TWDataBytes(digest.get()), kEmptySha256.data(),
                                 kEmptySha256.size()) == 0;
  return valid ? 0 : 3;
}

uint8_t wallet_engine_wallet_core_supports_json(uint32_t coin_type) {
  return TWAnySignerSupportsJSON(static_cast<TWCoinType>(coin_type)) ? 1 : 0;
}

int32_t wallet_engine_wallet_core_sign_json(
    uint32_t coin_type,
    const uint8_t* json,
    uint32_t json_length,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length) {
  if (json == nullptr || json_length == 0 || private_key == nullptr ||
      private_key_length != 32 || output_length == nullptr) {
    return 1;
  }
  if (!TWAnySignerSupportsJSON(static_cast<TWCoinType>(coin_type))) {
    return 2;
  }

  try {
    StringPtr input(TWStringCreateWithRawBytes(json, json_length));
    SensitiveDataPtr key(
        TWDataCreateWithBytes(private_key, private_key_length));
    if (input == nullptr || key == nullptr) {
      return 4;
    }

    StringPtr result(TWAnySignerSignJSON(
        input.get(), key.get(), static_cast<TWCoinType>(coin_type)));
    if (result == nullptr) {
      return 4;
    }

    const size_t required = TWStringSize(result.get());
    *output_length = static_cast<uint32_t>(required);
    if (output == nullptr || output_capacity < required) {
      return 3;
    }
    std::memcpy(output, TWStringUTF8Bytes(result.get()), required);
    return required == 0 ? 4 : 0;
  } catch (...) {
    return 4;
  }
}

int32_t wallet_engine_wallet_core_sign_secp256k1(
    const uint8_t* private_key,
    uint32_t private_key_length,
    const uint8_t* digest,
    uint32_t digest_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length) {
  if (private_key == nullptr || private_key_length != 32 ||
      digest == nullptr || digest_length != 32 || output == nullptr ||
      output_capacity < 65 || output_length == nullptr) {
    return 1;
  }
  try {
    SensitiveDataPtr key_data(
        TWDataCreateWithBytes(private_key, private_key_length));
    DataPtr digest_data(TWDataCreateWithBytes(digest, digest_length));
    if (key_data == nullptr || digest_data == nullptr) return 4;

    PrivateKeyPtr key(TWPrivateKeyCreateWithData(key_data.get()));
    if (key == nullptr) return 4;
    DataPtr signature(
        TWPrivateKeySign(key.get(), digest_data.get(), TWCurveSECP256k1));
    if (signature == nullptr || TWDataSize(signature.get()) != 65) return 4;

    *output_length = 65;
    std::memcpy(output, TWDataBytes(signature.get()), 65);
    return 0;
  } catch (...) {
    return 4;
  }
}

int32_t wallet_engine_wallet_core_sign_proto(
    uint32_t coin_type,
    const uint8_t* input,
    uint32_t input_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length) {
  if (input == nullptr || input_length == 0 || output_length == nullptr) {
    return 1;
  }
  try {
    SensitiveDataPtr input_data(TWDataCreateWithBytes(input, input_length));
    if (input_data == nullptr) return 4;
    DataPtr result(TWAnySignerSign(
        input_data.get(), static_cast<TWCoinType>(coin_type)));
    if (result == nullptr) return 4;
    const size_t required = TWDataSize(result.get());
    *output_length = static_cast<uint32_t>(required);
    if (output == nullptr || output_capacity < required) return 3;
    if (required == 0) return 4;
    std::memcpy(output, TWDataBytes(result.get()), required);
    return 0;
  } catch (...) {
    return 4;
  }
}

int32_t wallet_engine_wallet_core_sign_evm_message(
    uint32_t mode,
    const uint8_t* message,
    uint32_t message_length,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length) {
  if (mode > 2 || message == nullptr || message_length == 0 ||
      private_key == nullptr || private_key_length != 32 ||
      output_length == nullptr) {
    return 1;
  }
  try {
    StringPtr message_string(TWStringCreateWithRawBytes(message, message_length));
    SensitiveDataPtr key_data(TWDataCreateWithBytes(private_key, private_key_length));
    if (message_string == nullptr || key_data == nullptr) return 4;
    PrivateKeyPtr key(TWPrivateKeyCreateWithData(key_data.get()));
    if (key == nullptr) return 4;

    StringPtr signature;
    switch (mode) {
      case 0:
        signature.reset(TWEthereumMessageSignerSignMessage(
            key.get(), message_string.get()));
        break;
      case 1:
        signature.reset(TWEthereumMessageSignerSignTypedMessage(
            key.get(), message_string.get()));
        break;
      case 2:
        signature.reset(TWEthereumMessageSignerSignMessageImmutableX(
            key.get(), message_string.get()));
        break;
    }
    if (signature == nullptr) return 4;
    const size_t required = TWStringSize(signature.get());
    *output_length = static_cast<uint32_t>(required);
    if (output == nullptr || output_capacity < required) return 3;
    if (required == 0) return 4;
    std::memcpy(output, TWStringUTF8Bytes(signature.get()), required);
    return 0;
  } catch (...) {
    return 4;
  }
}

int32_t wallet_engine_wallet_core_derive_key(
    uint32_t coin_type,
    const uint8_t* mnemonic,
    uint32_t mnemonic_length,
    const uint8_t* passphrase,
    uint32_t passphrase_length,
    const uint8_t* derivation_path,
    uint32_t derivation_path_length,
    uint32_t public_key_mode,
    uint8_t* private_key_output,
    uint32_t private_key_capacity,
    uint32_t* private_key_length,
    uint8_t* public_key_output,
    uint32_t public_key_capacity,
    uint32_t* public_key_length,
    uint8_t* address_output,
    uint32_t address_capacity,
    uint32_t* address_length) {
  if (mnemonic == nullptr || mnemonic_length == 0 ||
      derivation_path == nullptr || derivation_path_length == 0 ||
      public_key_mode > 2 || private_key_length == nullptr ||
      public_key_length == nullptr || address_length == nullptr ||
      (passphrase == nullptr && passphrase_length != 0)) {
    return 1;
  }
  try {
    const uint8_t empty = 0;
    StringPtr mnemonic_string(
        TWStringCreateWithRawBytes(mnemonic, mnemonic_length));
    StringPtr passphrase_string(TWStringCreateWithRawBytes(
        passphrase == nullptr ? &empty : passphrase, passphrase_length));
    StringPtr path_string(
        TWStringCreateWithRawBytes(derivation_path, derivation_path_length));
    if (mnemonic_string == nullptr || passphrase_string == nullptr ||
        path_string == nullptr) {
      return 4;
    }
    HDWalletPtr wallet(TWHDWalletCreateWithMnemonicCheck(
        mnemonic_string.get(), passphrase_string.get(), true));
    if (wallet == nullptr) return 4;
    const auto coin = static_cast<TWCoinType>(coin_type);
    PrivateKeyPtr key(TWHDWalletGetKey(wallet.get(), coin, path_string.get()));
    if (key == nullptr) return 4;
    return ExportKeyInfo(
        coin, key.get(), public_key_mode, private_key_output,
        private_key_capacity, private_key_length, public_key_output,
        public_key_capacity, public_key_length, address_output,
        address_capacity, address_length);
  } catch (...) {
    return 4;
  }
}

int32_t wallet_engine_wallet_core_inspect_key(
    uint32_t coin_type,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint32_t public_key_mode,
    uint8_t* public_key_output,
    uint32_t public_key_capacity,
    uint32_t* public_key_length,
    uint8_t* address_output,
    uint32_t address_capacity,
    uint32_t* address_length) {
  if (private_key == nullptr || private_key_length == 0 ||
      public_key_mode > 2 || public_key_length == nullptr ||
      address_length == nullptr) {
    return 1;
  }
  try {
    SensitiveDataPtr key_data(
        TWDataCreateWithBytes(private_key, private_key_length));
    if (key_data == nullptr) return 4;
    PrivateKeyPtr key(TWPrivateKeyCreateWithData(key_data.get()));
    if (key == nullptr) return 4;
    std::array<uint8_t, 128> private_copy{};
    uint32_t private_copy_length = 0;
    const int32_t status = ExportKeyInfo(
        static_cast<TWCoinType>(coin_type), key.get(), public_key_mode,
        private_copy.data(), static_cast<uint32_t>(private_copy.size()),
        &private_copy_length, public_key_output, public_key_capacity,
        public_key_length, address_output, address_capacity, address_length);
    private_copy.fill(0);
    return status;
  } catch (...) {
    return 4;
  }
}

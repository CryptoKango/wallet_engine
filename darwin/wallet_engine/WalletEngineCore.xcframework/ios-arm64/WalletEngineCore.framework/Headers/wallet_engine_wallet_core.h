#ifndef WALLET_ENGINE_WALLET_CORE_H_
#define WALLET_ENGINE_WALLET_CORE_H_

#include <stdint.h>

#if defined(_WIN32)
#define WALLET_ENGINE_EXPORT __declspec(dllexport)
#else
#define WALLET_ENGINE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the version of the wallet_engine-owned C ABI.
WALLET_ENGINE_EXPORT uint32_t wallet_engine_wallet_core_abi_version(void);

/// Returns UTF-8 bytes compiled from WALLET_ENGINE_WALLET_CORE_VERSION.
WALLET_ENGINE_EXPORT const uint8_t*
wallet_engine_wallet_core_upstream_version(void);

WALLET_ENGINE_EXPORT uint32_t
wallet_engine_wallet_core_upstream_version_length(void);

/// Returns the full upstream Git commit compiled into this artifact.
WALLET_ENGINE_EXPORT const uint8_t*
wallet_engine_wallet_core_upstream_commit(void);

WALLET_ENGINE_EXPORT uint32_t
wallet_engine_wallet_core_upstream_commit_length(void);

/// Executes an SHA-256 known-answer test. Zero means success.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_self_test(void);

/// Returns one when the upstream coin dispatcher supports protobuf JSON.
WALLET_ENGINE_EXPORT uint8_t
wallet_engine_wallet_core_supports_json(uint32_t coin_type);

/// Signs a protobuf-JSON input. Output is the chain-specific encoded payload.
///
/// Status 0 is success, 1 invalid arguments, 2 unsupported coin, 3 output
/// buffer too small, and 4 upstream signing failure. On status 3,
/// `output_length` contains the required number of bytes.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_sign_json(
    uint32_t coin_type,
    const uint8_t* json,
    uint32_t json_length,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length);

/// Signs a 32-byte digest and returns a 65-byte recoverable secp256k1
/// signature. Status 0 means success.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_sign_secp256k1(
    const uint8_t* private_key,
    uint32_t private_key_length,
    const uint8_t* digest,
    uint32_t digest_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length);

/// Signs a serialized Wallet Core protobuf input and returns its serialized
/// protobuf output. The input can contain private key material and is wiped
/// from native temporary storage before release.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_sign_proto(
    uint32_t coin_type,
    const uint8_t* input,
    uint32_t input_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length);

/// Signs an Ethereum message. Mode: 0 personal, 1 EIP-712 V4, 2 Immutable X.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_sign_evm_message(
    uint32_t mode,
    const uint8_t* message,
    uint32_t message_length,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint8_t* output,
    uint32_t output_capacity,
    uint32_t* output_length);

/// Derives key material at an explicit path. Public-key mode: 0 coin default,
/// 1 compressed secp256k1, 2 Ed25519. Caller-owned output buffers are required.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_derive_key(
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
    uint32_t* address_length);

/// Validates private key bytes and returns its public key and default address.
WALLET_ENGINE_EXPORT int32_t wallet_engine_wallet_core_inspect_key(
    uint32_t coin_type,
    const uint8_t* private_key,
    uint32_t private_key_length,
    uint32_t public_key_mode,
    uint8_t* public_key_output,
    uint32_t public_key_capacity,
    uint32_t* public_key_length,
    uint8_t* address_output,
    uint32_t address_capacity,
    uint32_t* address_length);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // WALLET_ENGINE_WALLET_CORE_H_

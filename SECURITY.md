# Security policy

`wallet_engine` treats private-key access, RPC credentials, signed transaction
payloads, and remote configuration as security boundaries.

## Reporting

Report suspected vulnerabilities privately to the repository maintainers. Do
not include production private keys, seed phrases, RPC credentials, or complete
signed transactions in an issue, log, screenshot, or test fixture.

## Integration requirements

- Initialize Trust Wallet Core once during application startup.
- Persist newly created mnemonics and private keys only in platform-protected
  storage. `wallet_engine` intentionally does not cache or persist them.
- Never include `CreatedWallet`, mnemonics, BIP-39 passphrases, or private keys
  in logs, analytics, crash reports, screenshots, or RPC payloads.
- Validate imported private keys before protected persistence. Treat
  `WalletAccount.privateKey` returned from import as transient secret material
  and move it immediately behind `PrivateKeyAccess`.
- Watch-only accounts contain addresses only and must never be upgraded to
  signing accounts without an explicit key import or hardware/MPC enrollment.
- Keep private keys behind `PrivateKeyAccess` or a custom hardware/MPC signer.
- Supply RPC credentials at runtime through `RpcCredentialProvider`.
- Verify remote configuration signatures and expiry before applying snapshots.
- Call `verifyNetworkIdentities()` during startup for supported chains.
- Keep RPC body logging disabled in production. Redaction is defense in depth,
  not authorization to collect sensitive transaction payloads.
- Pin and audit dependency updates before releasing an application build.

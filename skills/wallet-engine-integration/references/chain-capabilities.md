# Chain capabilities

Always resolve a session from a configured chain key and use its concrete type:

```dart
final evm = engine.sessionAs<EvmChainSession>('ethereum');
final solana = engine.sessionAs<SolanaChainSession>('solana');
```

Call `verifyNetworkIdentities()` before enabling transaction submission. Use
`Decimal` for public amounts and convert to integer base units only at the RPC
or signing boundary.

## Implemented surface

| Protocol | RPC and transaction support | Signing support | Important constraint |
| --- | --- | --- | --- |
| EVM | Balances, calls, nonce, gas, legacy/EIP-1559 fees, prepare, broadcast, receipts | Transactions, personal messages, EIP-712/Hyperliquid | Contract ABI stays in the host adapter |
| Solana | Balance, SPL accounts/balances, blockhash, priority fee, rent, broadcast, receipts | SOL and SPL/Token-2022 transfers | Query all token accounts when computing total balance |
| Sui | Balance, paginated coins, gas/dry-run, broadcast, receipts | Raw JSON, `paySui`, and `pay` | Inject a production gRPC v2 `SuiGateway` |
| TRON | Balance, block header, native/contract build, constant calls, fees, broadcast, receipts | Exact `raw_data` and serialized transaction assembly | Preserve the node-provided raw bytes for signing |
| Bitcoin | Electrum UTXO, balance, fee rate, broadcast, confirmations | P2WPKH transfers and change inputs | Address handling is network-aware |
| Provenance | No RPC adapter | Cosmos-SDK JSON bank-send signature | Signing-only capability |

Aptos, TON, XRP, Cardano, Cosmos, Polkadot, and NEAR enum values are extension
points, not implemented RPC/transaction adapters. Do not advertise, configure,
or test them as supported protocols without adding the adapter and its tests.

## EVM transaction pattern

Keep contract encoding in the project adapter, then pass the encoded call to
the session:

```dart
final unsigned = await evm.prepareTransaction(
  EvmTransactionRequest(
    from: sender,
    to: contractAddress,
    value: Decimal.parse('0.125'),
    data: encodedProjectContractCall,
  ),
);

final submitted = await evm.signAndBroadcast(
  unsigned,
  signer: WalletCoreEvmSigner(
    privateKeyAccess: projectPrivateKeyAccess,
    runtime: initializedRuntime,
  ),
);

final receipt = await evm.waitForTransactionReceipt(
  submitted.transactionHash,
  confirmations: 2,
  policy: const TransactionConfirmationPolicy(
    timeout: Duration(minutes: 3),
    pollInterval: Duration(seconds: 2),
  ),
);
```

`projectPrivateKeyAccess`, `initializedRuntime`, and
`encodedProjectContractCall` are host-owned dependencies. The runtime must
already be initialized; signers never initialize it lazily.

## Solana associated token accounts

ATA derivation is local. Queries cover both the original SPL Token program and
Token-2022:

```dart
final ata = solana.deriveAssociatedTokenAddress(
  owner: owner,
  mint: mint,
  program: SolanaTokenProgram.token,
);
final account = await solana.getAssociatedTokenAccount(
  owner: owner,
  mint: mint,
);
final total = await solana.getTokenBalance(owner: owner, mint: mint);
```

`getTokenBalance` aggregates all matching accounts. Do not use the first token
account as a proxy for total ownership. For PDA owners, explicitly opt in with
`allowOwnerOffCurve: true`.

## Sui gateway selection

Foundation fullnodes do not provide the deprecated JSON-RPC path. Production
Apps must inject a current gRPC v2 gateway:

```dart
final adapters = walletEngineDefaultAdapters(
  sui: SuiChainAdapter(
    gatewayFactory: (config, rpc) => ProjectSuiGrpcGateway(config),
  ),
);
```

Use `LegacySuiJsonRpcGateway` only with a provider that explicitly guarantees
legacy compatibility. The engine owns and closes the injected gateway.

## Built-in test networks

`WalletEngineTestnetPreset.create()` contains Ethereum Sepolia, Solana Devnet,
TRON Nile, and Bitcoin Testnet. Sui is included only when the caller supplies
Sui endpoints, and that does not replace the production gRPC v2 requirement.
Public endpoints are for development and manual smoke tests, not deterministic
CI or production.

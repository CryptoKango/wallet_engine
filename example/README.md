# wallet_engine local example

用于在真实 Flutter 平台进程中验证 `wallet_engine` 和 Trust Wallet Core
原生绑定。页面覆盖：

- 12 / 24 词钱包创建
- BIP-39 英文词库查询与本地前缀提示
- BIP-39 助记词校验与账户恢复
- 私钥格式校验与账户导入
- 地址校验与 Watch-only 账户
- 当前链网络身份验证
- EVM / Solana / TRON / Bitcoin / Sui 只读 RPC 探针
- `WalletEngineConfigCodec` 配置快照导出
- SDK 结构化日志查看与清空
- Solana SPL Token / Token-2022 ATA 本地派生与链上查询
- Ethereum Sepolia、Solana Devnet、TRON Nile、Bitcoin Testnet、Sui Testnet

## 运行

```shell
cd example
flutter pub get
flutter run -d <ios-or-android-device-id>
```

连接 Android arm64 或 iOS 设备后，可通过 `flutter devices` 获取设备 ID。

这个示例只把敏感信息保存在页面内存中，不做本地持久化，也不会将助记词或
私钥写入调试日志。复制按钮会使用系统剪贴板，请测试后主动清理。不要输入任何
持有真实资产的助记词或私钥。

内置 RPC 是共享测试节点，只用于开发。页面不会在启动时自动发送 RPC 请求，
只有点击网络验证、只读 RPC 或 ATA 查询按钮才会访问节点。页面最多在内存中
保留 100 条脱敏 SDK 日志，请求/响应 body 默认关闭。Sui 地址/密钥功能可本地
测试，但正式链上调用仍需完成从旧 JSON-RPC 到官方 gRPC 的适配。

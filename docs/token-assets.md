# 代币资产查询

当前支持 TRON TRC20、Ethereum / Polygon / BNB ERC20（BEP20）、Solana SPL / Token-2022 的已添加 Mint 余额。资产列表展示原生币、预置代币及自定义代币，包含零余额；RPC 失败显示「查询失败」，不按零处理。不会自动枚举所有未知代币。

预置合约信息来源（2026-11-19 核对）：

- USDT Ethereum / TRON / Solana：https://tether.to/en/supported-protocols/
- USDC Ethereum / Polygon 原生 / Solana：https://developers.circle.com/stablecoins/usdc-contract-addresses
- Polygon USDT0：https://docs.usdt0.to/technical-documentation/deployments （原 Polygon USDT 地址升级后的名称）。
- BNB Binance-Peg BSC-USD：https://bscscan.com/token/0x55d398326f99059ff775485246999027b3197955
- BNB Binance-Peg USD Coin：https://bscscan.com/token/0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d

BNB 两个预置代币是 Binance-Peg 表示，分别按 18 位小数读取，不标为 Circle 原生 USDC。TRON 不预置已停止支持的旧 USDC；如仍需查看，可通过合约地址自行添加。Polygon 旧 USDC.e 与原生 USDC 不同，可作为自定义合约分别添加。

实现：EVM `eth_call balanceOf`；TRON `triggerconstantcontract balanceOf(address)`，参数移除 41 网络前缀后填充为 32 字节；Solana `getTokenAccountsByOwner` 依 Mint 查询、使用整数 amount 汇总所有匹配账户，校验账户拥有者、Token Program、Mint 和精度。

自定义合约先读取链上 decimals；EVM / TRON 可读取 symbol（支持动态字符串和 bytes32），Solana 使用用户显示名称。用户名称只是标签，不构成代币身份认证。配置按网络和合约地址去重，保存到 SharedPreferences 的 `linkwallet.tokens.v1`。移除自定义代币仅移除本地列表项。

已支持 ERC20 / BEP20 / TRC20 / 标准 SPL 代币转账。Token-2022 扩展代币仅可查询。暂不包含法币估值、历史代币流水及未知代币自动发现。

转账实现参考：

- ERC20 transfer 返回值：https://eips.ethereum.org/EIPS/eip-20
- TRON 能量与 fee_limit：https://developers.tron.network/docs/set-feelimit
- TRON 只读模拟：https://developers.tron.network/reference/triggerconstantcontract
- Solana TransferChecked：https://solana.com/docs/tokens/basics/transfer-tokens

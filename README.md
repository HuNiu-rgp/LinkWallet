# LinkWallet

面向个人使用的 macOS 多链钱包，使用 **Flutter + shadcn_ui** 开发。支持钱包管理、资产查询、收付款、代币转账，以及 TRON 质押、资源管理和投票。

当前版本：`1.0.2+3`。项目当前构建目标为 **Apple Silicon（arm64）与 macOS 12 及以上**。

> 项目仍处于开发阶段，尚未完成真实资金转账的完整端到端验证或独立安全审计。创建钱包后请保存加密备份，首次使用先进行小额验证。

## 功能概览

### 钱包管理

- 创建钱包，导入公开地址、十六进制私钥或加密备份。
- 钱包重命名、多地址管理、网络与钱包切换，左侧钱包支持拖拽排序并保存顺序。
- 观察钱包支持查询和收款，不具备签名权限。
- 地址 JSON 批量导入、导出。
- 私钥查看、加密私钥备份与恢复。
- 私钥保存在 macOS Keychain，应用不提供托管账户。

### 资产与转账

- 查询原生币和已添加代币的余额；应用运行期间每 3 分钟异步刷新当前选中钱包，避免重叠请求。
- 内置常用稳定币，支持按合约地址或 Solana Mint 添加自定义代币。
- 圆形币种 Logo、余额隐藏开关、资产刷新。
- 每个资产行提供对应币种的转账入口。
- 转账前预览金额、完整收款地址、代币合约及原生币费用。
- 收款二维码、地址复制、地址本与收款地址选择。
- 交易记录、交易详情与区块浏览器入口。
- K 线行情页面。

### TRON 资源与投票

- 查询可用 TRX、能量、带宽与质押状态。
- Stake 2.0 质押、解除质押、提取到期 TRX。
- 能量及带宽代理、代理资源回收。
- 查看自身质押、收到的代理及对外代理明细。
- 超级代表查询、投票分配及奖励领取。
- 质押与投票页面支持切换 TRON 钱包，并同步资产页的钱包选择。

### macOS 菜单栏与后台运行

- 顶部状态栏使用透明底 LinkWallet Logo，并提供原生“钱包”菜单。
- 查看当前钱包完整地址、网络与各币种余额；复制地址、切换钱包、刷新余额和打开主窗口。
- 隐藏主窗口后继续运行；从菜单选择“退出 LinkWallet”可完全退出。
- 设置中可开启或关闭钱包转账监控，并检查 macOS 通知权限。
- 监控按 60 秒间隔检查已添加钱包及资产币种；TRON 提醒已确认收付款，其他网络提醒余额变化。首次查询仅建立基准，不提醒旧记录。
- 轮询可能延迟；应用退出或电脑休眠时停止检查。

### 外观

- 浅色、深色与跟随系统。
- 森林绿、经典灰、海洋蓝、鸢尾紫、暖橙色五种主题配色。
- 自动保存外观偏好，页面、表格和弹窗同步适配。

## 支持的网络

| 网络 | 原生币 | 预置代币 | 代币转账 |
| --- | --- | --- | --- |
| TRON | TRX | USDT | TRC20 |
| Solana | SOL | USDT、USDC | 标准 SPL |
| Polygon | POL | USDT0、原生 USDC | ERC20 |
| BNB Chain | BNB | Binance-Peg USDT、USDC | BEP20 |
| Ethereum | ETH | USDT、USDC | ERC20 |

Token-2022 扩展代币目前支持已添加 Mint 的余额查询，暂不支持转账。预置代币与自定义代币按网络和合约地址区分；同名代币不代表同一资产。

合约来源和查询方式见 [代币说明](docs/token-assets.md)。

## 开发环境

- Apple Silicon Mac，macOS 12 或更新版本。
- Flutter SDK，其内置 Dart SDK 需满足 `pubspec.yaml` 中的 `^3.11.5` 约束。
- Xcode 及命令行工具。
- CocoaPods，用于 macOS 插件依赖安装。

在项目根目录检查环境：

```sh
flutter doctor -v
flutter devices
```

## 本地运行

```sh
flutter pub get
flutter run -d macos
```

首次运行时，系统可能请求钥匙串访问权限；钱包读取与签名需要能够访问相应 Keychain 项目。

## 构建 macOS 应用

```sh
flutter build macos --release
open build/macos/Build/Products/Release/LinkWallet.app
```

生成位置：

```text
build/macos/Build/Products/Release/LinkWallet.app
```

更新构建后，先使用 `⌘Q` 退出正在运行的旧版本，再打开新应用，确保加载最新代码与资源。当前构建配置为 arm64，不包含 Intel Mac 架构。

## 基本使用

### 1. 创建或导入钱包

选择网络后，点击「创建钱包」或「导入钱包」。导入公开地址得到观察钱包；导入私钥或恢复加密备份后，才可签名操作。

Solana 私钥导入目前使用 **32 字节 seed 的 64 位十六进制字符串**，不直接接受 base58 私钥或 64 字节 keypair 文件。当前未提供助记词导入与导出。

### 2. 备份钱包

在「设置与说明」中选择「备份当前钱包」，设置至少 12 位的独立密码并保存备份文件。

备份采用 V3 keystore 格式，使用 scrypt（`N=32768`）派生加密密钥，外层保存链类型和地址。TRON / EVM 备份保存 secp256k1 私钥，Solana 备份保存 Ed25519 seed。

**地址导出文件只包含公开地址和元数据，不能恢复私钥或签名权限。**

### 3. 查看资产与添加代币

从右上角切换网络，在钱包管理中选择地址。「我的资产」显示原生币、预置代币及自定义代币。

点击「添加代币」，输入对应网络的合约或 Mint 地址。应用会读取链上精度；Solana 自定义代币还需填写显示名称。自定义代币配置会保存到本机。

查询失败会明确提示，不按零余额处理。列表不会自动枚举所有未知代币。

### 4. 转账与收款

点击资产行右侧的「转账」，填写收款地址和金额，先预览再确认。预览中的费用使用该网络的原生币计价。

- ERC20 / BEP20：模拟合约转账、检查返回值并估算 gas。
- TRC20：模拟能量消耗，按当前费率与可用资源计算费用，并保留能量余量。
- 标准 SPL：使用 `TransferChecked`；必要时创建收款 ATA，预览包含相应租金。

预览通常在 45 秒后失效。广播结果不明确时，应先核对交易记录或区块浏览器，再决定是否重新提交。

收款时点击「收款」，复制地址或展示二维码，并确认发送方使用相同网络。

### 5. 质押、资源与投票

在 TRON 钱包的资产页面进入「质押与资源」或「投票」。页面顶部可选择其他 TRON 钱包；切换后重新读取该地址的数据和投票分配。

质押、解除质押、代理、回收、投票和领取操作均需在预览后确认签名。观察钱包仅可查看数据。解除质押的等待时间、资源兑换比例和费用以链上参数及执行结果为准。

## 数据存储与外部服务

| 数据 | 存储位置 |
| --- | --- |
| 私钥、钱包账户元数据 | macOS Keychain |
| 外观主题、自定义代币、地址本 | SharedPreferences |
| 导出的地址与加密备份 | 用户选择的本地文件 |

应用名称为 LinkWallet，Dart 包名仍为 `chainvault`，macOS Bundle ID 为 `com.personal.chainvault`。保留原标识和 Keychain 命名空间，以兼容已有钱包数据。

链上数据依赖公共 RPC、TronGrid 与 Blockscout；BNB 交易历史当前通过浏览器查看。行情依赖 TradingView / DexScreener。节点及第三方服务可能限流或不可用，访问这些服务会产生相应网络请求。

## 项目结构

```text
lib/
├── main.dart                  # 启动入口
├── app/                       # 应用根组件、桌面布局、主题与偏好
├── core/                      # 模型、存储、链服务、代币、转账与 TRON 治理
├── features/
│   ├── address_book/          # 地址本
│   ├── dashboard/             # 资产、余额卡、钱包列表与交易记录
│   ├── governance/            # 质押、资源明细与投票
│   ├── market/                # 行情页面
│   ├── settings/              # 设置与外观
│   ├── tokens/                # 代币配置与余额状态
│   ├── transfers/             # 转账表单、预览与签名流程
│   └── wallets/               # 钱包状态、创建导入与操作入口
└── shared/                    # 主题颜色、格式化函数与公共 UI 组件
assets/
├── brand/                     # LinkWallet Logo 源文件与 PNG
└── chains/                    # 网络与代币 Logo
macos/                         # macOS Runner、原生集成与应用图标
test/                          # 单元测试与 Widget 测试
docs/                          # 代币资料与实现说明
tool/                          # 图标生成等开发工具
```

界面使用 Flutter 的 `shadcn_ui` 移植库，包括 `ShadDialog`、`ShadInput`、`ShadSelect`、表格、标签页和按钮等组件。

## 检查与测试

```sh
flutter analyze
flutter test
```

测试涉及地址与密钥推导、金额精度、加密备份、代币余额、转账载荷与签名、TRON 资源与治理、钱包切换、地址本、主题持久化及界面交互。

转账和治理测试使用测试密钥与模拟节点；测试通过不等同于已经完成真实链上资金验证。

## 品牌资源

- 应用 Logo：`assets/brand/linkwallet.svg`、`assets/brand/linkwallet.png`。
- 链与代币 Logo：`assets/chains/`。
- macOS 应用图标：`macos/Runner/Assets.xcassets/AppIcon.appiconset/`。

在 macOS 上重新生成应用图标：

```sh
swift tool/generate_app_icons.swift
```

## 当前限制

- 暂无助记词、硬件钱包、跨链交换与资产法币总估值。
- 暂无额外应用密码或生物识别锁；应保护好当前 macOS 登录会话。
- Token-2022 扩展代币暂不支持转账；标准 SPL 单笔转账最多组合 4 个来源代币账户。
- 非标准代币、自定义合约及特殊扩展可能不兼容现有转账流程。
- 交易记录的范围取决于当前查询接口；部分记录、统计字段或行情可能不可用。
- 新增自定义代币的显示名称只是标签，代币身份应按网络与合约地址核对。

## 下载与安装

安装包发布在 [GitHub Releases](https://github.com/HuNiu-rgp/LinkWallet/releases)。当前提供 Apple Silicon（arm64）版本：

- **DMG**：打开后将 `LinkWallet.app` 拖入 `Applications`。
- **ZIP**：解压后将 `LinkWallet.app` 移入 `/Applications`。
- **SHA256SUMS**：用于校验下载文件完整性，将校验文件与安装包置于同一目录后执行 `shasum -a 256 -c SHA256SUMS`。

升级前先使用 `⌘Q` 退出旧版。当前开发预览版使用本地 ad-hoc 签名，未进行 Apple Developer ID 签名与公证；系统可能阻止从网络下载的应用运行。

开发者可运行以下脚本，依次完成依赖安装、静态检查、测试、Release 构建、签名完整性校验及 DMG / ZIP 打包：

```sh
./scripts/package_macos.sh
```

输出位于 `dist/`，该目录不提交到 Git；安装包作为 GitHub Release 附件分发。

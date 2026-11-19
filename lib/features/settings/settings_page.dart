import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/wallet_card.dart';
import '../../app/theme_controller.dart';
import '../wallets/wallet_controller.dart';
import '../wallets/wallet_actions.dart';
import 'appearance_settings.dart';

class SettingsPage extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  final ThemeController theme;
  const SettingsPage({
    super.key,
    required this.c,
    required this.actions,
    required this.theme,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '设置与说明',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 24),
      AppearanceSettings(controller: theme),
      SizedBox(height: 20),
      walletCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '密钥与备份',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Text(
              '钱包密钥保存在 macOS 钥匙串。创建后请导出加密备份；地址文件只包含公开地址，不能恢复转账权限。\n\n观察钱包无法转账。EVM 钱包可在 Ethereum、Polygon 和 BNB Chain 之间切换。Solana 私钥导入使用 32 字节 seed（十六进制）。',
              style: TextStyle(
                color: context.palette.mutedForeground,
                height: 1.8,
              ),
            ),
            SizedBox(height: 20),
            ShadButton.outline(
              onPressed: c.selected?.signing == true ? actions.backup : null,
              child: Text('备份当前钱包'),
            ),
          ],
        ),
      ),
      SizedBox(height: 20),
      walletCard(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本范围',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 12),
            Text(
              '五条主网原生币余额、收款与转账。TRON 手续费按 2 TRX 预留，实际费用由链上资源及账户状态决定。\n交易列表最多 25 条；BNB 记录通过浏览器查看。公共 RPC 可能限流。\n支持原生币、ERC20 / BEP20、TRC20 和标准 SPL 代币转账；Token-2022 扩展代币暂仅支持查询。助记词与硬件钱包尚未接入。\n\n这是开发版本，尚未完成真机小额转账验证或独立安全审计。',
              style: TextStyle(
                color: context.palette.mutedForeground,
                height: 1.8,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

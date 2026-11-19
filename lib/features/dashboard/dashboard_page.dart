import 'history_card.dart';
import 'wallet_list.dart';
import 'asset_card.dart';
import 'balance_card.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/wallet_card.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class DashboardPage extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const DashboardPage({super.key, required this.c, required this.actions});
  @override
  Widget build(BuildContext context) {
    if (c.booting) return Center(child: CircularProgressIndicator());
    if (c.startupError != null) {
      return walletCard(
        context,
        Column(
          children: [
            Text(c.startupError!),
            ShadButton.ghost(
              onPressed: () {
                c.update(() {
                  c.booting = true;
                  c.startupError = null;
                });
                c.load();
              },
              child: Text('重试'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ['你的资产，一目了然', '管理你的钱包', '链上活动记录'][c.page],
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: context.palette.foreground,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    c.page == 0 ? '一个安静、安全的多链资产空间。' : '所有数据来自所选网络，私钥只保存在本机。',
                    style: TextStyle(
                      color: context.palette.mutedForeground,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ShadButton.outline(
              onPressed: () => actions.addWallet(),
              child: Text('导入钱包'),
            ),
            SizedBox(width: 10),
            ShadButton(
              onPressed: () => actions.addWallet(create: true),
              child: Text('＋ 创建钱包'),
            ),
          ],
        ),
        SizedBox(height: 28),
        if (c.page == 1) ...[
          (c.accounts.isEmpty
              ? empty(context)
              : WalletList(c: c, actions: actions)),
          SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ShadButton.outline(
                onPressed: actions.importAddresses,
                child: Text('批量导入地址'),
              ),
              ShadButton.outline(
                onPressed: c.accounts.isEmpty ? null : actions.exportAddresses,
                child: Text('导出全部地址'),
              ),
            ],
          ),
        ] else if (c.selected == null)
          empty(context)
        else ...[
          if (c.page == 0) ...[
            BalanceCard(c: c, actions: actions),
            SizedBox(height: 24),
            AssetCard(c: c, actions: actions),
            SizedBox(height: 24),
          ],
          HistoryCard(c: c, actions: actions),
        ],
      ],
    );
  }

  Widget empty(BuildContext context) => walletCard(
    context,
    Padding(
      padding: EdgeInsets.symmetric(vertical: 65),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: context.palette.primary,
          ),
          SizedBox(height: 22),
          Text(
            '添加你的第一个 ${c.chain.name} 钱包',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Text(
            '导入地址以观察资产，或创建钱包来收款和转账。',
            style: TextStyle(color: context.palette.mutedForeground),
          ),
          SizedBox(height: 24),
          ShadButton(
            onPressed: () => actions.addWallet(create: true),
            child: Text('创建钱包'),
          ),
        ],
      ),
    ),
  );
}

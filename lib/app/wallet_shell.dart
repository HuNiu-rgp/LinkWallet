import 'package:flutter/material.dart';
import '../shared/theme_context.dart';
import '../shared/widgets/logos.dart';
import '../shared/widgets/network_selector.dart';
import '../features/wallets/wallet_controller.dart';
import 'theme_controller.dart';

class WalletShell extends StatelessWidget {
  final WalletController c;
  final ThemeController theme;
  final Widget child;
  const WalletShell({
    super.key,
    required this.c,
    required this.theme,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.palette.background,
    body: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return const Center(child: Text('请将窗口放大至至少 760 像素宽'));
        }
        return Row(
          children: [
            sidebar(context),
            Expanded(
              child: Column(
                children: [
                  topbar(context),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
  Widget sidebar(BuildContext context) => Container(
    width: 216,
    decoration: BoxDecoration(
      color: context.palette.card,
      border: Border(right: BorderSide(color: context.palette.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 34, 16, 36),
          child: Row(
            children: [
              BrandLogo(size: 32),
              SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'LinkWallet',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 26, bottom: 14),
          child: Text(
            '个人工作空间',
            style: TextStyle(
              fontSize: 11,
              color: context.palette.mutedForeground,
              letterSpacing: 1.5,
            ),
          ),
        ),
        nav(context, Icons.dashboard_outlined, '资产总览', 0),
        nav(context, Icons.account_balance_wallet_outlined, '钱包管理', 1),
        nav(context, Icons.swap_horiz_rounded, '交易记录', 2),
        nav(context, Icons.contacts_outlined, '地址本', 4),
        nav(context, Icons.settings_outlined, '设置与说明', 3),
        Spacer(),
        Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: context.palette.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本地存储 · 自己掌握',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 26, bottom: 20),
          child: Text(
            'LinkWallet / v0.1.0',
            style: TextStyle(
              fontSize: 10,
              color: context.palette.mutedForeground,
            ),
          ),
        ),
      ],
    ),
  );
  Widget nav(
    BuildContext context,
    IconData icon,
    String label,
    int index,
  ) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    child: InkWell(
      onTap: () => c.setPage(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.page == index ? context.palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: c.page == index
                  ? context.palette.primary
                  : context.palette.mutedForeground,
            ),
            SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: c.page == index
                    ? context.palette.primary
                    : context.palette.foreground,
                fontWeight: c.page == index ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget topbar(BuildContext context) => Container(
    height: 76,
    padding: EdgeInsets.symmetric(horizontal: 32),
    decoration: BoxDecoration(
      color: context.palette.card,
      border: Border(bottom: BorderSide(color: context.palette.border)),
    ),
    child: Row(
      children: [
        Text(
          ['资产总览', '钱包管理', '交易记录', '设置与说明', '地址本'][c.page],
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        Spacer(),
        NetworkSelector(value: c.chain, onChanged: c.selectChain),
      ],
    ),
  );
}

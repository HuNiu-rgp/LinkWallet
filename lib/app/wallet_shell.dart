import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shared/theme_context.dart';
import '../shared/widgets/logos.dart';
import '../shared/widgets/network_selector.dart';
import '../features/wallets/wallet_controller.dart';
import '../features/wallets/wallet_actions.dart';
import 'theme_controller.dart';
import 'wallet_sidebar.dart';
import '../core/models.dart';

class WalletShell extends StatelessWidget {
  final WalletController c;
  final ThemeController? theme;
  final String? title;
  final VoidCallback? onAddWallet;
  final Widget? leading;
  final bool scrollable;
  final ValueChanged<int>? onNavigate;
  final ValueChanged<Chain>? onNetworkChanged;
  final ValueChanged<Account>? onWalletChanged;
  final WalletActions actions;
  final Widget child;
  const WalletShell({
    super.key,
    required this.c,
    this.theme,
    this.title,
    this.onAddWallet,
    this.leading,
    this.scrollable = true,
    this.onNavigate,
    this.onNetworkChanged,
    this.onWalletChanged,
    required this.actions,
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
            _navigation(context),
            WalletSidebar(
              c: c,
              actions: actions,
              onSelected: onWalletChanged,
              onAdd: onAddWallet,
            ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.palette.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: 20),
                        ],
                        Text(
                          title ??
                              ['资产总览', '钱包管理', '交易记录', '设置与说明', '地址本'][c.page],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        NetworkSelector(
                          value: c.chain,
                          onChanged: onNetworkChanged ?? c.selectChain,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !scrollable
                        ? child
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
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

  Widget _navigation(BuildContext context) => Container(
    width: 64,
    decoration: BoxDecoration(
      color: context.palette.card,
      border: Border(right: BorderSide(color: context.palette.border)),
    ),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: BrandLogo(size: 34),
        ),
        const SizedBox(height: 12),
        _nav(context, LucideIcons.layoutDashboard, '资产总览', 0),
        _nav(context, LucideIcons.wallet, '钱包管理', 1),
        _nav(context, LucideIcons.arrowLeftRight, '交易记录', 2),
        _nav(context, LucideIcons.contact, '地址本', 4),
        const Spacer(),
        _nav(context, LucideIcons.settings, '设置与说明', 3),
        const SizedBox(height: 18),
      ],
    ),
  );

  Widget _nav(BuildContext context, IconData icon, String label, int index) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Tooltip(
          message: label,
          child: ShadButton.ghost(
            key: ValueKey('nav-$index'),
            width: 44,
            height: 44,
            padding: EdgeInsets.zero,
            backgroundColor: c.page == index
                ? context.palette.primary.withValues(alpha: .12)
                : null,
            foregroundColor: c.page == index
                ? context.palette.primary
                : context.palette.mutedForeground,
            onPressed: () => (onNavigate ?? c.setPage)(index),
            child: Icon(icon, size: 20, semanticLabel: label),
          ),
        ),
      );
}

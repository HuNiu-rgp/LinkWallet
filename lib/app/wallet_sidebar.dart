import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shared/theme_context.dart';
import '../core/models.dart';
import '../features/wallets/wallet_actions.dart';
import '../features/wallets/wallet_controller.dart';

/// Chain-scoped wallet selection stays available throughout the workspace.
class WalletSidebar extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  final ValueChanged<Account>? onSelected;
  final VoidCallback? onAdd;
  const WalletSidebar({
    super.key,
    required this.c,
    required this.actions,
    this.onSelected,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = c.accounts.where((a) => a.supportsChain(c.chain)).toList();
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(right: BorderSide(color: context.palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '我的钱包',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                ShadButton.ghost(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(LucideIcons.plus, size: 14),
                  onPressed: onAdd ?? () => actions.addWallet(),
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: context.palette.border,
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) async {
                final saved = await c.reorderWallets(oldIndex, newIndex);
                if (!saved && context.mounted) {
                  ShadSonner.of(context).show(
                    const ShadToast.destructive(title: Text('钱包排序保存失败，请重试')),
                  );
                }
              },
              proxyDecorator: (child, index, animation) => AnimatedBuilder(
                animation: animation,
                builder: (context, _) => Material(
                  color: context.palette.card,
                  elevation: 6 * animation.value,
                  borderRadius: BorderRadius.circular(8),
                  shadowColor: Colors.black.withValues(alpha: .25),
                  child: child,
                ),
              ),
              padding: const EdgeInsets.all(8),
              itemCount: accounts.length,
              itemBuilder: (context, index) {
                final account = accounts[index];
                final selected = account == c.selected;
                final address = account.address;
                final masked = address.length > 12
                    ? '${address.substring(0, 5)}…${address.substring(address.length - 4)}'
                    : address;
                return Padding(
                  key: ValueKey(
                    'wallet-order-${account.family.name}-${account.chainId}-${account.address}',
                  ),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ReorderableDragStartListener(
                    index: index,
                    enabled: !c.reorderingWallets,
                    child: Semantics(
                      selected: selected,
                      button: true,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('sidebar-wallet-${account.address}'),
                          onTap: () => (onSelected ?? c.selectAccount)(account),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? context.palette.primary.withValues(
                                      alpha: .10,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  width: 3,
                                  color: selected
                                      ? context.palette.primary
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  account.signing
                                      ? LucideIcons.wallet
                                      : LucideIcons.eye,
                                  size: 18,
                                  color: selected
                                      ? context.palette.primary
                                      : context.palette.mutedForeground,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        account.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        masked,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              context.palette.mutedForeground,
                                        ),
                                      ),
                                      if (!account.signing)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            '仅观察',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: context
                                                  .palette
                                                  .mutedForeground,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Tooltip(
                                  message: '拖拽排序',
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.grab,
                                    child: Icon(
                                      LucideIcons.gripVertical,
                                      size: 14,
                                      color: context.palette.mutedForeground
                                          .withValues(alpha: .65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '此网络暂无钱包',
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Row(
              children: [
                Icon(
                  LucideIcons.shieldCheck,
                  size: 14,
                  color: context.palette.mutedForeground,
                ),
                const SizedBox(width: 6),
                Text(
                  '本地存储 · 自己掌握',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.palette.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

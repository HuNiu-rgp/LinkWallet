import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../core/models.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

/// Compact wallet context and actions above the two portfolio columns.
class BalanceCard extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const BalanceCard({super.key, required this.c, required this.actions});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(bottom: 22),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      c.selected!.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ShadBadge.outline(
                      child: Text(
                        c.selected!.signing ? '签名钱包' : '仅观察',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        c.selected!.address,
                        style: TextStyle(
                          color: context.palette.mutedForeground,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: '复制地址',
                      child: ShadButton.ghost(
                        width: 30,
                        height: 30,
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          try {
                            await actions.copy(c.selected!.address);
                            if (!context.mounted) return;
                            ShadSonner.of(context).show(
                              const ShadToast(
                                title: Text('地址已复制'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            ShadSonner.of(context).show(
                              const ShadToast.destructive(
                                title: Text('复制地址失败，请重试'),
                              ),
                            );
                          }
                        },
                        child: const Icon(LucideIcons.copy, size: 14),
                      ),
                    ),
                  ],
                ),
              ],
            );
            final controls = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ShadButton(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(LucideIcons.arrowUpRight, size: 16),
                  onPressed: c.selected!.signing ? actions.send : null,
                  child: const Text('转账'),
                ),
                ShadButton.outline(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(LucideIcons.arrowDownLeft, size: 16),
                  onPressed: actions.receive,
                  child: const Text('收款'),
                ),
                if (c.chain.family == Family.tron) ...[
                  ShadButton.outline(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(LucideIcons.lockKeyhole, size: 15),
                    onPressed: () => actions.openTronGovernance(vote: false),
                    child: const Text('质押'),
                  ),
                  ShadButton.outline(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(LucideIcons.vote, size: 15),
                    onPressed: () => actions.openTronGovernance(vote: true),
                    child: const Text('投票'),
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [identity, const SizedBox(height: 12), controls],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 16),
                controls,
              ],
            );
          },
        ),
        if (c.chain.family == Family.tron) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _resource(
                  context,
                  '能量',
                  c.resources?.energy,
                  c.resources?.energyLimit,
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Tooltip(
                  message: '免费带宽与质押或委托获得的剩余带宽',
                  child: _resource(
                    context,
                    '带宽',
                    c.resources?.bandwidth,
                    c.resources?.bandwidthLimit,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: c.resourcesError ?? '刷新能量与带宽',
                child: ShadButton.ghost(
                  width: 32,
                  height: 32,
                  padding: EdgeInsets.zero,
                  onPressed: c.resourcesLoading ? null : c.refreshResources,
                  child: Icon(
                    c.resourcesError != null
                        ? LucideIcons.circleAlert
                        : LucideIcons.refreshCw,
                    size: 16,
                    color: c.resourcesError != null
                        ? context.palette.destructive
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (c.resourcesLoading || c.resourcesError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.resourcesLoading ? '正在查询资源…' : '资源查询失败，请重试',
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
        ],
      ],
    ),
  );

  Widget _resource(
    BuildContext context,
    String label,
    BigInt? available,
    BigInt? limit,
  ) {
    final ratio = available == null || limit == null || limit <= BigInt.zero
        ? 0.0
        : (available.toDouble() / limit.toDouble()).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  ${available ?? '—'} / ${limit ?? '—'}',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '可用$label',
          value: '${available ?? '未知'}，总额度 ${limit ?? '未知'}',
          child: ShadProgress(
            value: ratio,
            minHeight: 5,
            color: context.palette.primary,
            backgroundColor: context.palette.muted,
          ),
        ),
      ],
    );
  }
}

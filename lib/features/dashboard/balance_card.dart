import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../core/models.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class BalanceCard extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const BalanceCard({super.key, required this.c, required this.actions});
  @override
  Widget build(BuildContext context) {
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final foreground = dark
        ? context.palette.cardForeground
        : context.palette.primaryForeground;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: dark ? context.palette.muted : context.palette.primary,
        border: dark ? Border.all(color: context.palette.border) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.selected!.name} · ${c.selected!.signing ? '签名钱包' : '观察钱包'}',
                      style: TextStyle(color: foreground, fontSize: 12),
                    ),
                    SizedBox(height: 7),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SelectableText(
                            c.selected!.address,
                            style: TextStyle(
                              color: foreground.withValues(alpha: .8),
                              fontSize: 15,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '复制地址',
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
                              if (context.mounted) {
                                ShadSonner.of(context).show(
                                  const ShadToast.destructive(
                                    title: Text('复制地址失败，请重试'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: Icon(
                            Icons.copy_outlined,
                            size: 16,
                            color: foreground.withValues(alpha: .8),
                          ),
                        ),
                        IconButton(
                          tooltip: '显示地址二维码',
                          onPressed: actions.receive,
                          icon: Icon(
                            Icons.qr_code_2,
                            size: 18,
                            color: foreground.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                    if (c.chain.family == Family.tron) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _resourceProgress(
                            '能量',
                            c.resources?.energy,
                            c.resources?.energyLimit,
                            foreground,
                          ),
                          Tooltip(
                            message: '包含免费带宽与质押或委托获得的剩余带宽；进度表示可用比例',
                            child: _resourceProgress(
                              '带宽',
                              c.resources?.bandwidth,
                              c.resources?.bandwidthLimit,
                              foreground,
                            ),
                          ),
                          if (c.resourcesLoading)
                            Text(
                              '查询中…',
                              style: TextStyle(
                                color: foreground.withValues(alpha: .6),
                                fontSize: 12,
                              ),
                            ),
                          if (c.resourcesError != null)
                            Tooltip(
                              message: c.resourcesError!,
                              child: Text(
                                '资源查询失败',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .7),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: '刷新能量与带宽',
                            onPressed: c.resourcesLoading
                                ? null
                                : c.refreshResources,
                            icon: Icon(
                              Icons.refresh,
                              size: 16,
                              color: foreground,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 208,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    ShadButton(
                      onPressed: c.selected!.signing ? actions.send : null,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      backgroundColor: dark
                          ? context.palette.primary
                          : context.palette.primaryForeground,
                      hoverBackgroundColor:
                          (dark
                                  ? context.palette.primary
                                  : context.palette.primaryForeground)
                              .withValues(alpha: .85),
                      foregroundColor: dark
                          ? context.palette.primaryForeground
                          : context.palette.primary,
                      hoverForegroundColor: dark
                          ? context.palette.primaryForeground
                          : context.palette.primary,
                      leading: const Icon(Icons.north_east, size: 18),
                      child: const Text(
                        '转账',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ShadButton.outline(
                      onPressed: actions.receive,
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      backgroundColor: foreground.withValues(alpha: .05),
                      hoverBackgroundColor: foreground.withValues(alpha: .12),
                      foregroundColor: foreground,
                      hoverForegroundColor: foreground,
                      decoration: ShadDecoration(
                        border: ShadBorder.all(
                          color: foreground.withValues(alpha: .4),
                          radius: BorderRadius.circular(8),
                        ),
                      ),
                      leading: const Icon(Icons.south_west, size: 18),
                      child: const Text(
                        '收款',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (c.chain.family == Family.tron) ...[
                      _governanceButton(
                        '质押',
                        Icons.lock_outline,
                        foreground,
                        () => actions.openTronGovernance(vote: false),
                      ),
                      _governanceButton(
                        '投票',
                        Icons.how_to_vote_outlined,
                        foreground,
                        () => actions.openTronGovernance(vote: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _governanceButton(
    String label,
    IconData icon,
    Color foreground,
    VoidCallback onPressed,
  ) => ShadButton.outline(
    onPressed: onPressed,
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    backgroundColor: foreground.withValues(alpha: .05),
    hoverBackgroundColor: foreground.withValues(alpha: .12),
    foregroundColor: foreground,
    hoverForegroundColor: foreground,
    decoration: ShadDecoration(
      border: ShadBorder.all(
        color: foreground.withValues(alpha: .4),
        radius: BorderRadius.circular(8),
      ),
    ),
    leading: Icon(icon, size: 18),
    child: Text(
      label,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );

  Widget _resourceProgress(
    String label,
    BigInt? available,
    BigInt? limit,
    Color foreground,
  ) {
    final ratio = available == null || limit == null || limit <= BigInt.zero
        ? 0.0
        : (available.toDouble() / limit.toDouble()).clamp(0.0, 1.0);
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '可用$label  ${available ?? '—'} / ${limit ?? '—'}',
            style: TextStyle(color: foreground, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '可用$label',
            value: '${available ?? '未知'}，总额度 ${limit ?? '未知'}',
            child: ShadProgress(
              value: ratio,
              minHeight: 6,
              color: foreground.withValues(alpha: .85),
              backgroundColor: foreground.withValues(alpha: .15),
            ),
          ),
        ],
      ),
    );
  }
}

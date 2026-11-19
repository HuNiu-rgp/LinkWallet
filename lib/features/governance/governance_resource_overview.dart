import '../../shared/formatters.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import '../../core/tron_governance.dart';
import '../../shared/theme_context.dart';

/// Resource summary and paired actions, shared by all TRON wallet selections.
class GovernanceResourceOverview extends StatelessWidget {
  final String availableTrx;
  final TronResources resources;
  final Map account;
  final bool signing;
  final void Function(String kind, String resource) onOperate;
  const GovernanceResourceOverview({
    super.key,
    required this.availableTrx,
    required this.resources,
    required this.account,
    required this.signing,
    required this.onOperate,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Divider(height: 1, color: context.palette.border),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '可用 TRX',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$availableTrx TRX',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _progress(
                context,
                '能量',
                resources.energy,
                resources.energyLimit,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: _progress(
                context,
                '带宽',
                resources.bandwidth,
                resources.bandwidthLimit,
              ),
            ),
          ],
        ),
      ),
      Divider(height: 1, color: context.palette.border),
      LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              children: [
                _resource(context, 'ENERGY'),
                Divider(height: 1, color: context.palette.border),
                _resource(context, 'BANDWIDTH'),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _resource(context, 'ENERGY')),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: VerticalDivider(
                    width: 32,
                    color: context.palette.border,
                  ),
                ),
                Expanded(child: _resource(context, 'BANDWIDTH')),
              ],
            ),
          );
        },
      ),
      Divider(height: 1, color: context.palette.border),
    ],
  );

  Widget _progress(
    BuildContext context,
    String label,
    BigInt available,
    BigInt? total,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$label  $available / ${total ?? '—'}',
        style: const TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 10),
      Semantics(
        label: '可用$label',
        value: '$available，总额度 ${total ?? '未知'}',
        child: ShadProgress(
          minHeight: 5,
          value: total == null || total <= BigInt.zero
              ? 0
              : (available.toDouble() / total.toDouble()).clamp(0, 1),
          color: context.palette.primary,
          backgroundColor: context.palette.muted,
        ),
      ),
    ],
  );

  Widget _resource(BuildContext context, String resource) {
    final energy = resource == 'ENERGY';
    final stake = TronGovernance.stake(account, resource);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                energy ? LucideIcons.zap : LucideIcons.layers,
                size: 22,
                color: context.palette.primary,
              ),
              const SizedBox(width: 10),
              Text(
                energy ? '能量' : '带宽',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '自行质押：${formatBalance(stake, 6)} TRX',
            style: TextStyle(
              fontSize: 13,
              color: context.palette.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            children: [
              ShadButton(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: signing ? () => onOperate('stake', resource) : null,
                child: Text(energy ? '获取能量' : '获取带宽'),
              ),
              for (final entry in {
                'unstake': '解除质押',
                'delegate': '代理给他人',
                'undelegate': '收回代理',
              }.entries)
                ShadButton.ghost(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: signing
                      ? () => onOperate(entry.key, resource)
                      : null,
                  child: Text(entry.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

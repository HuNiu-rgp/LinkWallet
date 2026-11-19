import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/models.dart';
import 'logos.dart';

class NetworkSelector extends StatelessWidget {
  final Chain value;
  final ValueChanged<Chain> onChanged;
  const NetworkSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: '切换区块链网络',
    child: ShadSelect<Chain>(
      key: const ValueKey('network-selector'),
      initialValue: value,
      minWidth: 180,
      maxWidth: 200,
      options: Chain.all.map(
        (chain) => ShadOption<Chain>(
          value: chain,
          child: _NetworkLabel(chain: chain),
        ),
      ),
      selectedOptionBuilder: (context, chain) => _NetworkLabel(chain: chain),
      onChanged: (chain) {
        if (chain != null && chain != value) onChanged(chain);
      },
    ),
  );
}

class _NetworkLabel extends StatelessWidget {
  final Chain chain;
  const _NetworkLabel({required this.chain});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ChainLogo(chain: chain, size: 20),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          '${chain.name} 主网',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

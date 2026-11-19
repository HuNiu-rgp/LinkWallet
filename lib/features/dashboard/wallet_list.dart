import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/logos.dart';
import '../../shared/widgets/wallet_card.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class WalletList extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const WalletList({super.key, required this.c, required this.actions});
  @override
  Widget build(BuildContext context) => walletCard(
    context,
    Column(
      children: c.accounts
          .map(
            (a) => ListTile(
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              leading: ChainLogo(chain: a.preferredChain, size: 32),
              title: Text(a.name),
              subtitle: Text(
                '支持链：${Chain.all.where(a.supportsChain).map((chain) => chain.name).join(' / ')} · ${a.signing ? '签名钱包' : '仅观察'}\n${a.address}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.mutedForeground,
                ),
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShadButton.outline(
                    onPressed: () => actions.renameWallet(a),
                    child: const Text('修改'),
                  ),
                  const SizedBox(width: 8),
                  if (a.signing) ...[
                    ShadButton.outline(
                      onPressed: () => actions.viewPrivateKey(a),
                      child: const Text('查看私钥'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ShadButton.outline(
                    onPressed: () => c.selectAccount(a),
                    child: const Text('查看'),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

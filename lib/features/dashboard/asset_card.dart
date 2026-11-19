import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/token.dart';
import '../../shared/theme_context.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/logos.dart';
import '../../shared/widgets/token_logo.dart';
import '../../shared/widgets/wallet_card.dart';
import '../tokens/add_token_dialog.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class AssetCard extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const AssetCard({super.key, required this.c, required this.actions});
  Future<void> add(BuildContext context) async {
    final account = c.selected;
    if (account == null) return;
    final token = await showShadDialog<TokenDefinition>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddTokenDialog(
        chain: c.chain,
        owner: account.address,
        existingIds: c.tokens.balances.map((b) => b.token.id).toSet(),
      ),
    );
    if (token == null || !context.mounted) return;
    try {
      await c.tokens.add(token);
    } catch (_) {
      actions.notify('未能添加代币：可能已存在，或本地配置无法保存。请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => walletCard(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '我的资产',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '刷新资产',
              child: ShadButton.ghost(
                key: const ValueKey('refresh-assets'),
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed:
                    c.selected == null || c.assetsLoading || c.tokens.loading
                    ? null
                    : c.refreshAssets,
                child: c.assetsLoading || c.tokens.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
              ),
            ),
            const Spacer(),
            ShadButton.outline(
              onPressed: () => add(context),
              child: const Text('＋ 添加代币'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            ChainLogo(chain: c.chain, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                c.chain.symbol,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              fit: FlexFit.tight,
              child: Text(
                c.hidden
                    ? '••••'
                    : '${c.balance == null ? '—' : formatBalance(c.balance!, c.chain.decimals)} ${c.chain.symbol}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 20),
            _transferButton(),
            const SizedBox(width: 8),
            _tradeButton(),
          ],
        ),
        ...c.tokens.balances.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(top: 20),
            child: _tokenRow(context, entry),
          ),
        ),
        if (c.tokens.configurationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              c.tokens.configurationError!,
              style: TextStyle(color: context.palette.destructive),
            ),
          ),
        if (c.tokens.loading)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '正在查询代币余额…',
              style: TextStyle(
                color: context.palette.mutedForeground,
                fontSize: 11,
              ),
            ),
          ),
      ],
    ),
  );
  Widget _tokenRow(BuildContext context, TokenBalance entry) {
    final token = entry.token;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TokenLogo(token: token, size: 42),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            token.symbol,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            c.hidden
                ? '••••'
                : entry.error != null
                ? entry.error!
                : entry.amount == null
                ? '—'
                : '${formatBalance(entry.amount!, token.decimals)} ${token.symbol}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: entry.error == null
                  ? context.palette.foreground
                  : context.palette.destructive,
            ),
          ),
        ),
        const SizedBox(width: 20),
        if (entry.error != null)
          ShadButton.ghost(
            width: 30,
            onPressed: () => c.tokens.refresh(c.chain, c.selected?.address),
            child: const Icon(Icons.refresh, size: 15),
          ),
        if (token.custom)
          ShadButton.ghost(
            width: 30,
            onPressed: () async {
              try {
                await c.tokens.remove(token);
              } catch (_) {
                actions.notify('未能移除代币，请重试');
              }
            },
            child: const Icon(Icons.close, size: 15),
          ),
        _transferButton(token: token),
        const SizedBox(width: 8),
        _tradeButton(token: token),
      ],
    );
  }

  Widget _tradeButton({TokenDefinition? token}) => ShadButton.outline(
    key: ValueKey('trade-${token?.id ?? 'native'}'),
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    onPressed: () => actions.openChart(token: token),
    child: const Text('交易'),
  );

  Widget _transferButton({TokenDefinition? token}) => ShadButton.outline(
    key: ValueKey('transfer-${token?.id ?? 'native'}'),
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    onPressed: c.selected?.signing == true
        ? () => actions.send(token: token)
        : null,
    child: const Text('转账'),
  );
}

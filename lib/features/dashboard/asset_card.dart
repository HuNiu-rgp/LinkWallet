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
  final bool embedded;
  const AssetCard({
    super.key,
    required this.c,
    required this.actions,
    this.embedded = false,
  });
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
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '我的资产',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
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
            ShadButton.ghost(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              onPressed: () => add(context),
              child: const Text('＋ 添加代币'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            ChainLogo(chain: c.chain, size: 34),
            const SizedBox(width: 10),
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
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _transferButton(),
            _actionDivider(context),
            _tradeButton(),
          ],
        ),
        Divider(height: 24, color: context.palette.border),
        ...c.tokens.balances.map(
          (entry) => Padding(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _tokenRow(context, entry),
                Divider(height: 24, color: context.palette.border),
              ],
            ),
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
    );
    return embedded ? content : walletCard(context, content);
  }

  Widget _tokenRow(BuildContext context, TokenBalance entry) {
    final token = entry.token;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TokenLogo(token: token, size: 34),
        const SizedBox(width: 10),
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
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: entry.error == null
                  ? context.palette.foreground
                  : context.palette.destructive,
            ),
          ),
        ),
        const SizedBox(width: 8),
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
        _actionDivider(context),
        _tradeButton(token: token),
      ],
    );
  }

  Widget _actionDivider(BuildContext context) => SizedBox(
    width: 8,
    height: 16,
    child: VerticalDivider(
      width: 8,
      thickness: 1,
      color: context.palette.border,
    ),
  );

  Widget _tradeButton({TokenDefinition? token}) => ShadButton.ghost(
    key: ValueKey('trade-${token?.id ?? 'native'}'),
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    onPressed: () => actions.openChart(token: token),
    child: const Text('交易'),
  );

  Widget _transferButton({TokenDefinition? token}) => ShadButton.ghost(
    key: ValueKey('transfer-${token?.id ?? 'native'}'),
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    onPressed: c.selected?.signing == true
        ? () => actions.send(token: token)
        : null,
    child: const Text('转账'),
  );
}

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/wallet_card.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class HistoryCard extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  const HistoryCard({super.key, required this.c, required this.actions});
  @override
  Widget build(BuildContext context) => walletCard(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '最近交易',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Spacer(),
            if (c.chain.id == 137)
              ShadButton.ghost(
                onPressed: c.selected == null ? null : () => actions.browse(),
                leading: const Icon(Icons.open_in_new, size: 15),
                child: const Text('浏览器查看'),
              ),
            IconButton(
              tooltip: '刷新交易记录',
              onPressed: c.historyLoading ? null : c.refreshHistory,
              icon: Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: c.hideSmallTransactions,
              onChanged: (value) => c.setHideSmallTransactions(value ?? true),
              visualDensity: VisualDensity.compact,
            ),
            GestureDetector(
              onTap: () => c.setHideSmallTransactions(!c.hideSmallTransactions),
              child: Text(
                '隐藏小额交易',
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: '隐藏金额小于 1 个对应币种的转账（非折合法币金额）。金额未知的记录保留。仅筛选已加载的最近 25 条记录。',
              child: Icon(
                Icons.help_outline,
                size: 14,
                color: context.palette.mutedForeground,
              ),
            ),
          ],
        ),
        Divider(color: context.palette.border),
        if (c.historyError != null && c.transactions.isEmpty)
          Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              c.historyError!,
              style: TextStyle(color: context.palette.mutedForeground),
            ),
          )
        else if (c.transactions.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                c.historyLoading ? '正在获取链上记录…' : '该网络暂无交易记录',
                style: TextStyle(
                  color: context.palette.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else if (c.visibleTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                '小额交易已隐藏，关闭筛选可查看',
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
          )
        else
          ...c.visibleTransactions
              .take(c.page == 2 ? 25 : 5)
              .map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => actions.viewTransaction(t),
                  title: Text(
                    t['amount'] == null
                        ? '${t['detail']}'
                        : '${t['incoming'] == true ? '收款' : '付款'} (${_address(t['counterparty'] as String? ?? '')})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _time('${t['timestamp']}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.mutedForeground,
                      ),
                    ),
                  ),
                  trailing: t['amount'] == null
                      ? Text(
                          '${t['status']}',
                          style: const TextStyle(fontSize: 11),
                        )
                      : Tooltip(
                          message: '${t['symbol']} · ${t['status']}',
                          child: Text(
                            '${t['pending'] == true ? '待确认 · ' : ''}${t['incoming'] == true ? '+' : '-'}${_amount(t['amount'] as String)} ${t['symbol']}',
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  t['status'] != 'SUCCESS' &&
                                      t['status'] != '已确认'
                                  ? context.palette.mutedForeground
                                  : t['incoming'] == true
                                  ? const Color(0xFF00BF45)
                                  : const Color(0xFFE55353),
                            ),
                          ),
                        ),
                ),
              ),
      ],
    ),
  );
}

String _address(String value) => value.length <= 12
    ? value
    : '${value.substring(0, 6)}...${value.substring(value.length - 5)}';

String _time(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  return date == null ? value : date.toString().split('.').first;
}

String _amount(String value) {
  final parts = value.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

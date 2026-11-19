import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/wallet_card.dart';
import '../wallets/wallet_actions.dart';
import '../wallets/wallet_controller.dart';

class HistoryCard extends StatelessWidget {
  final WalletController c;
  final WalletActions actions;
  final bool embedded;
  const HistoryCard({
    super.key,
    required this.c,
    required this.actions,
    this.embedded = false,
  });
  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '最近交易',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Spacer(),
            Tooltip(
              message: '隐藏金额小于 1 个对应币种的转账（非折合法币金额）。仅筛选已加载记录。',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '隐藏小额',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ShadSwitch(
                    value: c.hideSmallTransactions,
                    onChanged: c.setHideSmallTransactions,
                  ),
                ],
              ),
            ),
            if (c.chain.id == 137 && !embedded)
              ShadButton.ghost(
                onPressed: c.selected == null ? null : () => actions.browse(),
                leading: const Icon(Icons.open_in_new, size: 15),
                child: const Text('浏览器查看'),
              ),
            Tooltip(
              message: '刷新交易记录',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed: c.historyLoading ? null : c.refreshHistory,
                child: const Icon(LucideIcons.refreshCw, size: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                c.historyLoading ? '正在获取链上记录…' : '暂无资产收款或转账记录',
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
                '暂无符合筛选条件的收款或转账记录',
                style: TextStyle(
                  fontSize: 13,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
          )
        else
          ...c.pagedTransactions.map((t) => _transaction(context, t)),
        if (c.historyError != null && c.transactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              c.historyError!,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.destructive,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '第 ${c.historyPage + 1} 页 · 每页 7 条',
              style: TextStyle(
                fontSize: 11,
                color: context.palette.mutedForeground,
              ),
            ),
            const Spacer(),
            ShadButton.outline(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: c.historyLoading || c.historyPage == 0
                  ? null
                  : c.previousHistoryPage,
              child: const Text('上一页'),
            ),
            const SizedBox(width: 8),
            ShadButton.outline(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: c.historyLoading || !c.canGoForwardHistory
                  ? null
                  : c.nextHistoryPage,
              child: Text(c.historyLoading ? '查询中…' : '下一页'),
            ),
          ],
        ),
      ],
    );
    return embedded ? content : walletCard(context, content);
  }

  Widget _transaction(BuildContext context, Map<String, dynamic> t) {
    final incoming = t['incoming'] == true;
    final hasAmount = t['amount'] != null;
    final success = t['status'] == 'SUCCESS' || t['status'] == '已确认';
    final color = !hasAmount || !success
        ? context.palette.mutedForeground
        : incoming
        ? context.palette.primary
        : context.palette.destructive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => actions.viewTransaction(t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.palette.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .12),
                ),
                child: Icon(
                  !hasAmount
                      ? LucideIcons.activity
                      : incoming
                      ? LucideIcons.arrowDown
                      : LucideIcons.arrowUp,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasAmount
                          ? '${t['pending'] == true ? '待确认 · ' : ''}${incoming ? '+' : '-'}${_amount(t['amount'] as String)} ${t['symbol']}'
                          : '${t['detail']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasAmount
                          ? '${incoming ? '来自' : '发送至'}  ${_address(t['counterparty'] as String? ?? '')}'
                          : '${t['status']}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: _time('${t['timestamp']}'),
                child: Text(
                  _compactTime('${t['timestamp']}'),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

String _compactTime(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = day.difference(target).inDays;
  final clock =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return days == 0
      ? '今天 $clock'
      : days == 1
      ? '昨天 $clock'
      : '${date.month}/${date.day} $clock';
}

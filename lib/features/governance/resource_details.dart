import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/tron_governance.dart';
import '../../core/wallet.dart';
import '../../shared/formatters.dart';
import 'dart:math' as math;

typedef ResourceOperation =
    Future<void> Function(String kind, String resource, String? receiver);

class ResourceDetails extends StatefulWidget {
  final TronGovernance api;
  final Account owner;
  final Map account, resources;
  final ResourceOperation onOperate;
  const ResourceDetails({
    super.key,
    required this.api,
    required this.owner,
    required this.account,
    required this.resources,
    required this.onOperate,
  });
  @override
  State<ResourceDetails> createState() => _ResourceDetailsState();
}

class _ResourceDetailsState extends State<ResourceDetails> {
  int tab = 0;
  String filter = '';
  Future<List<Map<String, dynamic>>>? request;
  void select(int value) {
    setState(() {
      tab = value;
      filter = '';
      request = value == 0
          ? null
          : widget.api.resourceDelegations(
              widget.owner.address,
              incoming: value == 1,
            );
    });
  }

  String estimate(BigInt sun, String resource) {
    final value = TronGovernance.resourceEstimate(
      sun,
      resource,
      widget.resources,
    );
    return value == null ? '—' : '≈ $value';
  }

  String expiry(BigInt timestamp) => timestamp == BigInt.zero
      ? '无锁定资源'
      : DateTime.fromMillisecondsSinceEpoch(
          timestamp.toInt(),
          isUtc: true,
        ).toString().split('.').first;

  @override
  Widget build(BuildContext context) => ShadCard(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const title = Text(
              '资源明细',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            );
            final tabs = SizedBox(
              width: constraints.maxWidth < 420 ? constraints.maxWidth : 420,
              child: ShadTabs<int>(
                value: tab,
                onChanged: select,
                tabBarAlignment: Alignment.centerLeft,
                tabs: const [
                  ShadTab(value: 0, child: Text('质押获得')),
                  ShadTab(value: 1, child: Text('他人代理给自己')),
                  ShadTab(value: 2, child: Text('代理给他人')),
                ],
              ),
            );
            return constraints.maxWidth >= 620
                ? Row(children: [title, const Spacer(), tabs])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), tabs],
                  );
          },
        ),
        const SizedBox(height: 12),
        if (tab == 2) ...[
          ShadInput(
            key: ValueKey(tab),
            placeholder: const Text('搜索接收账户地址'),
            onChanged: (value) =>
                setState(() => filter = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
        ],
        if (tab == 0)
          table(
            ['资源类型', '获取资源数量', '质押数量', '最后操作时间 (UTC)', '操作'],
            [
              for (final resource in ['BANDWIDTH', 'ENERGY'])
                DataRow(
                  cells: [
                    DataCell(Text(resource == 'ENERGY' ? '能量' : '带宽')),
                    DataCell(
                      Text(
                        estimate(
                          TronGovernance.stake(widget.account, resource),
                          resource,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${formatEther(TronGovernance.stake(widget.account, resource), 6)} TRX',
                      ),
                    ),
                    const DataCell(Text('—')),
                    DataCell(
                      ShadButton.outline(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed:
                            widget.owner.signing &&
                                TronGovernance.stake(widget.account, resource) >
                                    BigInt.zero
                            ? () => widget.onOperate('unstake', resource, null)
                            : null,
                        child: const Text('解除质押'),
                      ),
                    ),
                  ],
                ),
            ],
          )
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Row(
                  children: [
                    const Expanded(child: Text('代理明细查询失败，请重试')),
                    ShadButton.ghost(
                      onPressed: () => select(tab),
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              final rows = snapshot.data!
                  .where(
                    (r) => (r['peer'] as String).toLowerCase().contains(filter),
                  )
                  .toList();
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(filter.isEmpty ? '暂无数据' : '无匹配账户')),
                );
              }
              return table(
                [
                  tab == 1 ? '代理账户' : '接收账户',
                  '代理资源数量',
                  '资源类型',
                  '解锁时间 (UTC)',
                  '占用 TRX',
                  if (tab == 2) ...['使用率（昨日）', '燃烧 TRX（昨日）'],
                  '最后操作时间 (UTC)',
                  if (tab == 2) '操作',
                ],
                [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(
                          Tooltip(
                            message: row['peer'] as String,
                            child: SelectableText(short(row['peer'] as String)),
                          ),
                        ),
                        DataCell(
                          Text(
                            estimate(
                              row['sun'] as BigInt,
                              row['resource'] as String,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(row['resource'] == 'ENERGY' ? '能量' : '带宽'),
                        ),
                        DataCell(Text(expiry(row['expires'] as BigInt))),
                        DataCell(Text(formatEther(row['sun'] as BigInt, 6))),
                        if (tab == 2) ...[
                          const DataCell(Text('—')),
                          const DataCell(Text('—')),
                        ],
                        const DataCell(Text('—')),
                        if (tab == 2)
                          DataCell(
                            ShadButton.outline(
                              height: 32,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              onPressed:
                                  widget.owner.signing &&
                                      (row['expires'] as BigInt) <=
                                          BigInt.from(
                                            DateTime.now()
                                                .millisecondsSinceEpoch,
                                          )
                                  ? () => widget.onOperate(
                                      'undelegate',
                                      row['resource'] as String,
                                      row['peer'] as String,
                                    )
                                  : null,
                              child: Text(
                                (row['expires'] as BigInt) >
                                        BigInt.from(
                                          DateTime.now().millisecondsSinceEpoch,
                                        )
                                    ? '锁定中'
                                    : '收回',
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 12),
        const Text(
          'Stake 2.0 明细；资源数量按当前全网兑换比例估算。最后操作时间及昨日统计暂无数据，以 — 显示。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
  Widget table(List<String> headers, List<DataRow> rows) {
    final hasActions = headers.last == '操作';
    final dataColumns = headers.length - (hasActions ? 1 : 0);
    final palette = ShadTheme.of(context).colorScheme;
    double baseWidth(String label) => switch (label) {
      '操作' => 128,
      '代理账户' || '接收账户' => 210,
      '解锁时间 (UTC)' || '最后操作时间 (UTC)' => 180,
      '资源类型' => 100,
      _ => 140,
    };
    Widget section(List<int> columns, String name) => LayoutBuilder(
      builder: (context, constraints) {
        final total = columns.fold(
          0.0,
          (sum, i) => sum + baseWidth(headers[i]),
        );
        final spare = math.max(0.0, constraints.maxWidth - total);
        return ShadTable.list(
          key: ValueKey('resource-table-$tab-$name'),
          primary: false,
          verticalScrollPhysics: const NeverScrollableScrollPhysics(),
          pinnedRowCount: 1,
          columnSpanExtent: (column) => FixedTableSpanExtent(
            baseWidth(headers[columns[column]]) + spare / columns.length,
          ),
          rowSpanExtent: (row) => FixedTableSpanExtent(row == 0 ? 36 : 44),
          rowSpanBackgroundDecoration: (row) => row == 0
              ? TableSpanDecoration(color: palette.muted.withValues(alpha: .6))
              : null,
          header: [
            for (final i in columns)
              ShadTableCell.header(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  headers[i],
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.mutedForeground,
                  ),
                ),
              ),
          ],
          children: [
            for (final row in rows)
              [
                for (final i in columns)
                  ShadTableCell(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: row.cells[i].child,
                  ),
              ],
          ],
        );
      },
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 36 + rows.length * 44.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: section(List.generate(dataColumns, (i) => i), 'data'),
            ),
            if (hasActions)
              SizedBox(
                width: 128,
                child: section([headers.length - 1], 'actions'),
              ),
          ],
        ),
      ),
    );
  }
}

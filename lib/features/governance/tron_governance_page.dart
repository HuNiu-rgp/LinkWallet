import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import 'resource_details.dart';
import '../../core/tron_governance.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/formatters.dart';
import 'governance_operation_dialog.dart';
export 'governance_operation_dialog.dart';
import 'governance_resource_overview.dart';
import 'representative_row.dart';
import '../../shared/widgets/back_to_assets_button.dart';
import '../../shared/widgets/wallet_account_selector.dart';

class TronGovernancePage extends StatefulWidget {
  final Account account;
  final List<Account> accounts;
  final WalletStore store;
  final bool vote;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onVoteChanged;
  final ChainService? service;
  final ValueChanged<Account>? onAccountChanged;
  final Widget Function(
    Widget child,
    ValueChanged<Account> onWalletChanged,
    bool voting,
  )?
  workspaceBuilder;
  const TronGovernancePage({
    super.key,
    required this.account,
    this.accounts = const [],
    required this.store,
    required this.vote,
    this.embedded = false,
    this.onClose,
    this.onVoteChanged,
    this.service,
    this.onAccountChanged,
    this.workspaceBuilder,
  });
  @override
  State<TronGovernancePage> createState() => _TronGovernancePageState();
}

class _TronGovernancePageState extends State<TronGovernancePage> {
  late final service =
      widget.service ??
      ChainService(Chain.all.firstWhere((c) => c.family == Family.tron));
  late final api = TronGovernance(service);
  late Account selectedAccount = widget.account;
  int _loadRevision = 0;
  List<Account> get walletOptions => {
    for (final account in [widget.account, ...widget.accounts, selectedAccount])
      if (account.supportsChain(service.chain)) account.address: account,
  }.values.toList();

  void switchAccount(Account account) {
    if (account.address == selectedAccount.address) return;
    setState(() {
      selectedAccount = account;
      data = null;
      allocation = {};
      query = '';
      onlyMine = false;
    });
    widget.onAccountChanged?.call(account);
    load();
  }

  Map<String, dynamic>? data;
  Map<String, BigInt> allocation = {};
  bool loading = true, onlyMine = false;
  String? error;
  String query = '';
  late bool voting = widget.vote;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant TronGovernancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vote != oldWidget.vote) voting = widget.vote;
    if (widget.account.address != oldWidget.account.address ||
        widget.account.signing != oldWidget.account.signing) {
      selectedAccount = widget.account;
      data = null;
      allocation = {};
      query = '';
      onlyMine = false;
      load();
    }
  }

  @override
  void dispose() {
    _loadRevision++;
    service.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final revision = ++_loadRevision;
    final address = selectedAccount.address;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await api.load(address);
      if (mounted && revision == _loadRevision) {
        setState(() {
          data = result;
          allocation = TronGovernance.votes(result['account'] as Map);
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() {
          loading = false;
          error = '链上数据加载失败，请重试';
        });
      }
    }
  }

  BigInt n(Object? value) => TronGovernance.number(value);
  String trx(Object? value) => formatBalance(n(value), 6);
  Map get account => data!['account'] as Map;
  Map get resources => data!['resources'] as Map;
  BigInt get totalPower {
    if (resources['tronPowerLimit'] != null) {
      return n(resources['tronPowerLimit']);
    }
    final legacy = (account['frozen'] as List? ?? []).fold(
      BigInt.zero,
      (sum, f) => sum + n(f['frozen_balance']),
    );
    return (legacy +
            n(
              account['account_resource']?['frozen_balance_for_energy']?['frozen_balance'],
            ) +
            TronGovernance.stake(account, 'ENERGY') +
            TronGovernance.stake(account, 'BANDWIDTH') +
            n(account['delegated_frozenV2_balance_for_bandwidth']) +
            n(
              account['account_resource']?['delegated_frozenV2_balance_for_energy'],
            )) ~/
        BigInt.from(1000000);
  }

  BigInt get assigned => allocation.values.fold(BigInt.zero, (a, b) => a + b);
  Future<void> operate(
    String kind, {
    String resource = 'ENERGY',
    String? receiver,
  }) async {
    final changed = await showShadDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => GovernanceOperationDialog(
        api: api,
        accounts: widget.accounts,
        initialReceiver: receiver,
        account: selectedAccount,
        store: widget.store,
        kind: kind,
        resource: resource,
        votes: Map.of(allocation),
        totalPower: totalPower,
        unstakeDays:
            (data!['parameters'] as List)
                .where((p) => p['key'] == 'getUnfreezeDelayDays')
                .firstOrNull?['value']
                ?.toString() ??
            '以链上参数为准',
      ),
    );
    if (changed == true && mounted) await load();
  }

  Future<void> editVotes(Map witness) async {
    final address = oc.TronAddress(witness['address'] as String).address;
    final controller = TextEditingController(
      text: (allocation[address] ?? BigInt.zero).toString(),
    );
    String? validation;
    final count = await showShadDialog<BigInt>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => ShadDialog(
          title: const Text('设置投票数量'),
          constraints: const BoxConstraints(maxWidth: 520),
          actions: [
            ShadButton.ghost(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ShadButton(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () {
                final count = BigInt.tryParse(controller.text.trim());
                if (count == null ||
                    count < BigInt.zero ||
                    assigned - (allocation[address] ?? BigInt.zero) + count >
                        totalPower) {
                  update(() => validation = '票数需为非负整数，且分配总数不能超过总票权');
                  return;
                }
                Navigator.pop(ctx, count);
              },
              child: const Text('确定'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(address),
              const SizedBox(height: 6),
              LinkInput(controller: controller, label: '票数（0 表示取消该代表的投票）'),
              if (validation != null)
                Text(
                  validation!,
                  style: TextStyle(color: context.palette.destructive),
                ),
            ],
          ),
        ),
      ),
    );
    if (count != null && mounted) {
      setState(() {
        if (count == BigInt.zero) {
          allocation.remove(address);
        } else {
          allocation[address] = count;
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final identity =
                  !widget.embedded && widget.workspaceBuilder == null
                  ? WalletAccountSelector(
                      value: selectedAccount,
                      accounts: walletOptions,
                      onChanged: switchAccount,
                    )
                  : Row(
                      children: [
                        const Icon(LucideIcons.wallet, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            selectedAccount.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: selectedAccount.address,
                          child: Text(
                            short(selectedAccount.address),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.mutedForeground,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: '复制钱包地址',
                          child: ShadButton.ghost(
                            width: 28,
                            height: 28,
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              try {
                                await Clipboard.setData(
                                  ClipboardData(text: selectedAccount.address),
                                );
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
                        if (!selectedAccount.signing)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: ShadBadge.outline(child: Text('仅观察')),
                          ),
                      ],
                    );
              final tabs = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 224,
                    child: ShadTabs<bool>(
                      value: voting,
                      onChanged: (value) {
                        setState(() => voting = value);
                        widget.onVoteChanged?.call(value);
                      },
                      tabs: [
                        ShadTab(
                          value: false,
                          selectedBackgroundColor: context.palette.primary,
                          selectedForegroundColor:
                              context.palette.primaryForeground,
                          child: const Text('质押与资源'),
                        ),
                        ShadTab(
                          value: true,
                          selectedBackgroundColor: context.palette.primary,
                          selectedForegroundColor:
                              context.palette.primaryForeground,
                          child: const Text('投票'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '刷新链上数据',
                    child: ShadButton.ghost(
                      width: 32,
                      height: 32,
                      padding: EdgeInsets.zero,
                      onPressed: loading ? null : load,
                      child: const Icon(LucideIcons.refreshCw, size: 16),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < (widget.embedded ? 760 : 650)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.embedded) ...[
                      BackToAssetsButton(onPressed: widget.onClose),
                      const SizedBox(height: 12),
                    ],
                    identity,
                    const SizedBox(height: 12),
                    tabs,
                  ],
                );
              }
              return Row(
                children: [
                  if (widget.workspaceBuilder == null) ...[
                    BackToAssetsButton(onPressed: widget.onClose),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  tabs,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!),
                        ShadButton(onPressed: load, child: const Text('重试')),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: voting ? votesView(context) : stakeView(context),
                  ),
          ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return widget.workspaceBuilder?.call(content, switchAccount, voting) ??
        Scaffold(
          backgroundColor: context.palette.background,
          body: SafeArea(child: content),
        );
  }

  Widget _panel(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: child);

  Widget stat(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.palette.mutedForeground,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
  Widget stakeView(BuildContext context) {
    final r = TronResources.fromJson(Map<String, dynamic>.from(resources));
    final pending = account['unfrozenV2'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GovernanceResourceOverview(
          availableTrx: trx(account['balance']),
          resources: r,
          account: account,
          signing: selectedAccount.signing,
          onOperate: (kind, resource) => operate(kind, resource: resource),
        ),
        const SizedBox(height: 24),
        ResourceDetails(
          key: ObjectKey(data),
          embedded: true,
          api: api,
          owner: selectedAccount,
          account: account,
          resources: resources,
          onOperate: (kind, resource, receiver) =>
              operate(kind, resource: resource, receiver: receiver),
        ),
        const SizedBox(height: 12),
        Divider(height: 32, color: context.palette.border),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '解锁中的质押',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                ShadButton.outline(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed:
                      selectedAccount.signing &&
                          pending.any(
                            (e) =>
                                n(e['unfreeze_expire_time']) <=
                                BigInt.from(
                                  DateTime.now().millisecondsSinceEpoch,
                                ),
                          )
                      ? () => operate('withdraw')
                      : null,
                  child: const Text('提取已到期 TRX'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (pending.isEmpty)
              Text(
                '暂无解锁记录',
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedForeground,
                ),
              ),
            ...pending.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${e['type'] == 'ENERGY' ? '能量' : '带宽'} · ${trx(e['unfreeze_amount'])} TRX · 到期 ${DateTime.fromMillisecondsSinceEpoch(n(e['unfreeze_expire_time']).toInt()).toLocal()}',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget votesView(BuildContext context) {
    final original = TronGovernance.votes(account);
    final witnesses = (data!['witnesses'] as List).cast<Map>().toList()
      ..sort((a, b) => n(b['voteCount']).compareTo(n(a['voteCount'])));
    final filtered = witnesses.where((w) {
      final address = oc.TronAddress(w['address'] as String).address;
      return (!onlyMine ||
              (allocation[address] ?? BigInt.zero) > BigInt.zero) &&
          ('$address ${w['url']}'.toLowerCase().contains(query.toLowerCase()));
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          Column(
            children: [
              Row(
                children: [
                  stat('总票权', '$totalPower'),
                  stat('已分配 / 剩余', '$assigned / ${totalPower - assigned}'),
                  stat('待领奖励', '${trx(data!['reward'])} TRX'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ShadButton.outline(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed:
                        selectedAccount.signing &&
                            n(data!['reward']) > BigInt.zero
                        ? () => operate('reward')
                        : null,
                    child: const Text('领取奖励'),
                  ),
                  const Spacer(),
                  ShadButton(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed:
                        selectedAccount.signing &&
                            assigned > BigInt.zero &&
                            assigned <= totalPower
                        ? () => operate('vote')
                        : null,
                    child: const Text('预览并提交投票'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 24, color: context.palette.border),
        Text(
          '修改后统一提交，将替换完整投票分配；未修改的原有投票会保留。',
          style: TextStyle(
            fontSize: 12,
            color: context.palette.mutedForeground,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ShadInput(
                placeholder: const Text('搜索代表地址或网址'),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(width: 8),
            ShadButton.outline(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () => setState(() => onlyMine = !onlyMine),
              child: Text(onlyMine ? '显示全部' : '仅我的投票'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _panel(
          Column(
            children: [
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有匹配的超级代表'),
                ),
              ...filtered.map((w) {
                final address = oc.TronAddress(w['address'] as String).address;
                return RepresentativeRow(
                  address: address,
                  name: w['url']?.toString() ?? address,
                  networkVotes: '${w['voteCount'] ?? 0}',
                  originalVotes: '${original[address] ?? BigInt.zero}',
                  allocatedVotes: '${allocation[address] ?? BigInt.zero}',
                  onEdit: selectedAccount.signing ? () => editVotes(w) : null,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

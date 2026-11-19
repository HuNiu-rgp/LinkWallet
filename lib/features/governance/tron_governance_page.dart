import 'package:flutter/material.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import 'resource_details.dart';
import '../../core/tron_governance.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/logos.dart';
import '../../shared/widgets/wallet_card.dart';
import '../../shared/widgets/back_to_assets_button.dart';
import '../../shared/widgets/wallet_account_selector.dart';

class TronGovernancePage extends StatefulWidget {
  final Account account;
  final List<Account> accounts;
  final WalletStore store;
  final bool vote;
  final ChainService? service;
  final ValueChanged<Account>? onAccountChanged;
  const TronGovernancePage({
    super.key,
    required this.account,
    this.accounts = const [],
    required this.store,
    required this.vote,
    this.service,
    this.onAccountChanged,
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
  String trx(Object? value) => formatEther(n(value), 6);
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const BackToAssetsButton(),
                const SizedBox(width: 8),
                Expanded(
                  child: WalletAccountSelector(
                    value: selectedAccount,
                    accounts: walletOptions,
                    onChanged: switchAccount,
                  ),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => setState(() => voting = false),
                  child: Text(voting ? '质押与资源' : '✓ 质押与资源'),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => setState(() => voting = true),
                  child: Text(voting ? '✓ 投票' : '投票'),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: loading ? null : load,
                  child: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      ShadButton(onPressed: load, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: voting ? votesView(context) : stakeView(context),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget _panel(Widget child) =>
      walletCard(context, child, padding: const EdgeInsets.all(16));

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
        Row(
          children: [
            const Text(
              '质押获取资源',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '质押 TRX 获取能量或带宽，并参与超级代表投票。',
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _panel(
          Row(
            children: [
              stat('可用 TRX', trx(account['balance'])),
              stat('可用能量 / 总能量', '${r.energy} / ${r.energyLimit}'),
              stat('可用带宽 / 总带宽', '${r.bandwidth} / ${r.bandwidthLimit}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final resource in ['ENERGY', 'BANDWIDTH']) ...[
              if (resource == 'BANDWIDTH') const SizedBox(width: 8),
              Expanded(
                child: _panel(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource == 'ENERGY' ? '我的能量' : '我的带宽',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '自行质押：${formatEther(TronGovernance.stake(account, resource), 6)} TRX',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ShadButton(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: selectedAccount.signing
                                ? () => operate('stake', resource: resource)
                                : null,
                            child: Text(resource == 'ENERGY' ? '获取能量' : '获取带宽'),
                          ),
                          ShadButton.outline(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: selectedAccount.signing
                                ? () => operate('unstake', resource: resource)
                                : null,
                            child: const Text('解除质押'),
                          ),
                          ShadButton.outline(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: selectedAccount.signing
                                ? () => operate('delegate', resource: resource)
                                : null,
                            child: const Text('代理给他人'),
                          ),
                          ShadButton.ghost(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            onPressed: selectedAccount.signing
                                ? () =>
                                      operate('undelegate', resource: resource)
                                : null,
                            child: const Text('收回代理'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ResourceDetails(
          key: ObjectKey(data),
          api: api,
          owner: selectedAccount,
          account: account,
          resources: resources,
          onOperate: (kind, resource, receiver) =>
              operate(kind, resource: resource, receiver: receiver),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '解锁中的质押',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
              if (pending.isEmpty) const Text('暂无解锁记录'),
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
        const Text(
          '投票',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
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
        const Text('修改票数后统一提交；提交会替换全部投票分配。未改动的原有投票会保留。'),
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
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  title: Text(w['url']?.toString() ?? address),
                  subtitle: Text(
                    '$address\n全网票数：${w['voteCount'] ?? 0} · 链上已投：${original[address] ?? BigInt.zero}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: ShadButton.outline(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: selectedAccount.signing
                        ? () => editVotes(w)
                        : null,
                    child: Text('分配 ${allocation[address] ?? BigInt.zero} 票'),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class GovernanceOperationDialog extends StatefulWidget {
  final TronGovernance api;
  final Account account;
  final List<Account> accounts;
  final WalletStore store;
  final String kind, resource, unstakeDays;
  final String? initialReceiver;
  final Map<String, BigInt> votes;
  final BigInt totalPower;
  const GovernanceOperationDialog({
    super.key,
    required this.api,
    this.accounts = const [],
    this.initialReceiver,
    required this.account,
    required this.store,
    required this.kind,
    required this.resource,
    required this.votes,
    required this.totalPower,
    required this.unstakeDays,
  });
  @override
  State<GovernanceOperationDialog> createState() =>
      _GovernanceOperationDialogState();
}

class _GovernanceOperationDialogState extends State<GovernanceOperationDialog> {
  final amount = TextEditingController(), receiver = TextEditingController();
  TransferQuote? quote;
  BigInt? previewSun;
  String amountUnit = 'RESOURCE';
  late Future<DelegationBudget> delegationRequest;
  late Future<BigInt> stakeBalance = widget.api.service.balance(
    widget.account.address,
  );
  @override
  void initState() {
    super.initState();
    receiver.text = widget.initialReceiver ?? '';
    if (reclaimAll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) preview();
      });
    }
    if (widget.kind == 'delegate') {
      delegationRequest = widget.api.delegationBudget(
        widget.account.address,
        widget.resource,
      );
      delegationRequest.ignore();
    }
  }

  bool busy = false, attempted = false, sent = false;
  String? error, hash;
  String get title => switch (widget.kind) {
    'stake' => '质押 TRX',
    'unstake' => '解除质押',
    'delegate' => '代理资源',
    'undelegate' => '收回代理',
    'withdraw' => '提取已到期 TRX',
    'reward' => '领取投票奖励',
    _ => '提交投票',
  };
  bool get reclaimAll =>
      widget.kind == 'undelegate' && widget.initialReceiver != null;
  bool get needsAmount =>
      ['stake', 'unstake', 'delegate', 'undelegate'].contains(widget.kind);
  bool get needsReceiver => ['delegate', 'undelegate'].contains(widget.kind);
  @override
  void dispose() {
    amount.dispose();
    receiver.dispose();
    super.dispose();
  }

  Future<void> selectReceiverWallet() async {
    final seen = <String>{};
    final wallets = widget.accounts
        .where(
          (a) =>
              a.family == Family.tron &&
              a.address != widget.account.address &&
              seen.add(a.address),
        )
        .toList();
    final selected = await showShadDialog<Account>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('选择资源接收钱包'),
        constraints: const BoxConstraints(maxWidth: 600),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
        child: SizedBox(
          width: 520,
          child: wallets.isEmpty
              ? const Text('暂无其他 TRON 钱包，可在钱包管理中添加，或手动输入接收地址。')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: wallets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final wallet = wallets[index];
                        return ListTile(
                          leading: ChainLogo(chain: wallet.preferredChain),
                          title: Text(wallet.name),
                          subtitle: Text(
                            wallet.address,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(ctx, wallet),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        receiver.text = selected.address;
        error = null;
        quote = null;
      });
    }
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      BigInt? value;
      if (reclaimAll) {
        value = await widget.api.reclaimableStake(
          widget.account.address,
          receiver.text.trim(),
          widget.resource,
        );
        if (value <= BigInt.zero) {
          throw const FormatException('当前没有可收回额度，可能仍在锁定中或已被收回');
        }
      } else if (needsAmount) {
        if (widget.kind == 'delegate' && amountUnit == 'RESOURCE') {
          final units = BigInt.tryParse(amount.text.trim());
          if (units == null) throw const FormatException('能量或带宽数量需为正整数');
          // Refresh the conversion and maximum at preview time.
          final budget = await widget.api.delegationBudget(
            widget.account.address,
            widget.resource,
          );
          value = budget.sunForResource(units);
        } else {
          value = parseEther(amount.text.trim(), 6);
        }
      }
      if (widget.kind == 'vote' &&
          widget.votes.values.fold(BigInt.zero, (a, b) => a + b) >
              widget.totalPower) {
        throw const FormatException('分配票数超过票权');
      }
      final contract = TronGovernance.contract(
        widget.kind,
        widget.account.address,
        resource: widget.resource,
        amount: value,
        receiver: receiver.text.trim(),
        votes: widget.votes,
      );
      final result = await widget.api.preview(
        widget.account,
        contract,
        spend: widget.kind == 'stake' ? value : null,
      );
      if (mounted) {
        setState(() {
          quote = result;
          previewSun = value;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is FormatException ? e.message : '预览失败，请检查数量、地址、余额和网络',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (quote == null) return;
    if (DateTime.now().difference(quote!.created).inSeconds > 45) {
      setState(() {
        quote = null;
        error = '预览已过期，请重新预览';
      });
      return;
    }
    setState(() {
      busy = true;
      attempted = true;
      error = null;
    });
    try {
      final result = await widget.api.send(
        widget.account,
        widget.store,
        quote!,
      );
      if (mounted) {
        setState(() {
          hash = result;
          sent = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '未能确认广播结果，请先在交易记录或区块浏览器核对，避免重复操作。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ShadDialog(
      title: Text(title),
      closeIcon: const SizedBox.shrink(),
      constraints: const BoxConstraints(maxWidth: 600),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actions: [
        ShadButton.ghost(
          onPressed: busy
              ? null
              : () => Navigator.pop(context, sent || attempted),
          child: Text(attempted ? '关闭并刷新' : '取消'),
        ),
        if (!attempted)
          ShadButton(
            onPressed: busy
                ? null
                : quote == null
                ? preview
                : send,
            child: Text(
              busy
                  ? '处理中…'
                  : quote == null
                  ? '预览操作'
                  : '确认并签名发送',
            ),
          ),
      ],
      child: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('钱包：${widget.account.name} · TRON 主网'),
              const SizedBox(height: 12),
              if (sent) ...[
                const Text('交易已广播，等待链上确认。'),
                const SizedBox(height: 12),
                SelectableText(hash!),
              ] else if (quote == null) ...[
                if (needsAmount && !reclaimAll) ...[
                  Text('资源类型：${widget.resource == 'ENERGY' ? '能量' : '带宽'}'),
                  const SizedBox(height: 12),
                  if (widget.kind == 'stake') ...[
                    FutureBuilder<BigInt>(
                      future: stakeBalance,
                      builder: (context, snapshot) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              snapshot.connectionState != ConnectionState.done
                                  ? '可用 TRX：查询中…'
                                  : snapshot.hasError
                                  ? '可用 TRX：查询失败，请重试'
                                  : '可用：${formatEther(snapshot.data!, 6)} TRX',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.mutedForeground,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新可用 TRX',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.refresh, size: 16),
                            onPressed:
                                busy ||
                                    snapshot.connectionState !=
                                        ConnectionState.done
                                ? null
                                : () => setState(
                                    () => stakeBalance = widget.api.service
                                        .balance(widget.account.address),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.kind == 'delegate') ...[
                    LinkSelect<String>(
                      label: '输入单位',
                      value: amountUnit,
                      enabled: !busy,
                      options: {
                        'RESOURCE': widget.resource == 'ENERGY'
                            ? '能量数量'
                            : '带宽数量',
                        'TRX': '质押 TRX 对应的资源',
                      },
                      onChanged: (value) => setState(() {
                        amountUnit = value;
                        amount.clear();
                        error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<DelegationBudget>(
                      future: delegationRequest,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final b = snapshot.data!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '可用代理${widget.resource == 'ENERGY' ? '能量' : '带宽'}：≈ ${b.estimatedMaxResource}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.palette.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '对应 ${formatEther(b.maxSun, 6)} TRX 质押额度，资源数量随链上比例变化。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.mutedForeground,
                                ),
                              ),
                            ],
                          );
                        }
                        return Text(
                          snapshot.hasError
                              ? '可用代理${widget.resource == 'ENERGY' ? '能量' : '带宽'}读取失败，预览时将重新查询'
                              : '正在查询可用代理${widget.resource == 'ENERGY' ? '能量' : '带宽'}…',
                          style: const TextStyle(fontSize: 12),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  LinkInput(
                    controller: amount,
                    label: widget.kind == 'delegate'
                        ? amountUnit == 'RESOURCE'
                              ? '${widget.resource == 'ENERGY' ? '能量' : '带宽'}数量（整数）'
                              : '代理质押额度（TRX，至少 1 TRX）'
                        : '数量（TRX，至少 1 TRX）',
                    enabled: !busy,
                  ),
                  const SizedBox(height: 16),
                ],
                if (needsReceiver && !reclaimAll) ...[
                  Text('资源接收地址', style: ShadTheme.of(context).textTheme.small),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ShadInput(
                          controller: receiver,
                          enabled: !busy,
                          autocorrect: false,
                          enableSuggestions: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '选择其他钱包',
                        child: ShadButton.outline(
                          key: const ValueKey('select-resource-wallet'),
                          onPressed: busy ? null : selectReceiverWallet,
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (reclaimAll) ...[
                  Text(
                    '收回该地址当前全部可回收的${widget.resource == 'ENERGY' ? '能量' : '带宽'}代理额度',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(receiver.text),
                  const SizedBox(height: 12),
                  const Text('锁定期内额度不包含在本次回收中。'),
                ],
                if (widget.kind == 'vote') ...[
                  const Text('本次完整投票分配：'),
                  ...widget.votes.entries.map(
                    (e) => SelectableText('${e.key}：${e.value} 票'),
                  ),
                ],
              ] else ...[
                const Text(
                  '请核对操作',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '${reclaimAll ? '回收范围：该地址全部可回收的${widget.resource == 'ENERGY' ? '能量' : '带宽'}\n' : ''}操作：$title\n钱包：${widget.account.address}\n${needsAmount ? '资源：${widget.resource}\n质押额度：${formatEther(previewSun!, 6)} TRX${widget.kind == 'delegate' && amountUnit == 'RESOURCE' ? '（约 ${amount.text} ${widget.resource == 'ENERGY' ? '能量' : '带宽'}）' : ''}\n' : ''}${needsReceiver ? '接收地址：${receiver.text}\n' : ''}手续费保守预留：${formatEther(quote!.fee, 6)} TRX',
                ),
                if (widget.kind == 'vote')
                  ...widget.votes.entries.map(
                    (e) => SelectableText('${e.key}：${e.value} 票'),
                  ),
                const SizedBox(height: 12),
                const Text('此预览估算带宽费用，未广播交易；链上执行仍可能失败。报价 45 秒内有效。'),
              ],
              if (widget.kind == 'unstake')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '解除质押会减少资源和票权，可能影响已投票数。等待期：${widget.unstakeDays} 天；到期后需另行提取。',
                  ),
                ),
              if (widget.kind == 'delegate')
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('代理的是资源使用权，TRX 所有权保留；本次不设置代理锁定。'),
                ),
              if (widget.kind == 'vote')
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('本次提交将替换全部原有投票分配。'),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SelectableText(
                    error!,
                    style: TextStyle(color: context.palette.destructive),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

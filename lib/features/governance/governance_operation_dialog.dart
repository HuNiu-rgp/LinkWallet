import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import '../../core/tron_governance.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/logos.dart';

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

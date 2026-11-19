import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';
import '../../core/address_book.dart';
import '../../core/token.dart';
import '../../core/token_service.dart';
import '../../shared/formatters.dart';
import '../../core/token_transfer_service.dart';
import '../../core/token_transfer_quote.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/logos.dart';
import '../../shared/widgets/token_logo.dart';

class SendDialog extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>>? onBroadcast;
  final Account account;
  final Chain chain;
  final WalletStore store;
  final TokenDefinition? token;
  final List<TokenDefinition> tokens;
  const SendDialog({
    super.key,
    required this.account,
    required this.chain,
    required this.store,
    this.onBroadcast,
    this.token,
    this.tokens = const [],
  });
  @override
  State<SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<SendDialog> {
  final to = TextEditingController(), amount = TextEditingController();
  late final service = ChainService(widget.chain);
  late TokenDefinition? token = widget.token;
  late final Map<String, TokenDefinition> availableTokens = {
    for (final t in [...widget.tokens, if (widget.token != null) widget.token!])
      if (t.chainId == widget.chain.id) t.id: t,
  };
  TransferQuote? quote;
  BigInt? units;
  String? destination, error;
  bool busy = false, uncertain = false;
  String get symbol => token?.symbol ?? widget.chain.symbol;
  int get decimals => token?.decimals ?? widget.chain.decimals;
  late Future<BigInt> balanceRequest = loadBalance();
  int balanceVersion = 0;

  Future<BigInt> loadBalance() {
    final request = token == null
        ? service.balance(widget.account.address)
        : TokenService(service).balance(token!, widget.account.address);
    // The request may fail before the rebuilt FutureBuilder subscribes.
    request.ignore();
    return request;
  }

  @override
  void dispose() {
    to.dispose();
    amount.dispose();
    service.dispose();
    super.dispose();
  }

  Future<void> selectRecipient() async {
    var request = AddressBookRepository().load();
    var query = '';
    final entry = await showShadDialog<AddressEntry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => ShadDialog(
          title: const Text('选择收款地址'),
          description: Text('从地址本选择 ${widget.chain.name} 网络的收款地址'),
          constraints: const BoxConstraints(maxWidth: 560),
          gap: 20,
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShadInput(
                  placeholder: const Text('搜索名称或地址'),
                  leading: Icon(
                    Icons.search,
                    size: 18,
                    color: ctx.palette.mutedForeground,
                  ),
                  onChanged: (value) =>
                      update(() => query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 16),
                FutureBuilder<List<AddressEntry>>(
                  future: request,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('地址本读取失败，请重试'),
                          const SizedBox(height: 12),
                          ShadButton.outline(
                            onPressed: () => update(
                              () => request = AddressBookRepository().load(),
                            ),
                            child: const Text('重试'),
                          ),
                        ],
                      );
                    }
                    final entries = snapshot.data!
                        .where(
                          (e) =>
                              e.chainId == widget.chain.id &&
                              (e.name.toLowerCase().contains(query) ||
                                  e.address.toLowerCase().contains(query)),
                        )
                        .toList();
                    if (entries.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          query.isEmpty
                              ? '当前网络暂无保存的地址，请到“地址本”添加。'
                              : '未找到匹配的名称或地址',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: ctx.palette.mutedForeground),
                        ),
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${entries.length} 个地址',
                          style: TextStyle(
                            fontSize: 12,
                            color: ctx.palette.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(ctx).height * .4,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return LayoutBuilder(
                                builder: (context, constraints) =>
                                    ShadButton.ghost(
                                      height: 76,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(ctx, entry),
                                      child: SizedBox(
                                        width: constraints.maxWidth - 24,
                                        child: Row(
                                          children: [
                                            ChainLogo(
                                              chain: entry.chain,
                                              size: 32,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    entry.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    entry.address,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontFamily: 'monospace',
                                                      color: ctx
                                                          .palette
                                                          .mutedForeground,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 18,
                                              color:
                                                  ctx.palette.mutedForeground,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (entry != null && mounted) {
      setState(() {
        to.text = entry.address;
        quote = null;
        destination = null;
        error = null;
      });
    }
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final target = validateAddress(to.text, widget.chain.family);
      final value = parseEther(amount.text, decimals);
      final q =
          await (token == null
                  ? service.quote(widget.account.address, target, value)
                  : TokenTransferService(
                      service,
                    ).quote(token!, widget.account.address, target, value))
              .timeout(const Duration(seconds: 90));
      if (mounted) {
        setState(() {
          quote = q;
          units = value;
          destination = target;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException ? e.message : '无法预览：请检查收款地址、金额、余额及网络连接。';
        });
      }
    }
  }

  Future<void> broadcast() async {
    if (quote == null ||
        DateTime.now().difference(quote!.created).inSeconds > 45) {
      setState(() {
        quote = null;
        error = '预览已过期，请重新预览';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    var attempted = false;
    try {
      final secret = await widget.store.secret(widget.account);
      attempted = true;
      final hash = token == null
          ? await service.send(secret, destination!, units!, quote!)
          : await TokenTransferService(
              service,
            ).send(quote! as TokenTransferQuote, secret);
      widget.onBroadcast?.call({
        'hash': hash,
        'status': '待确认',
        'pending': true,
        'timestamp': DateTime.now().toLocal().toString(),
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
        'incoming': false,
        'counterparty': destination,
        'from': widget.account.address,
        'to': destination,
        'amount': formatEther(units!, decimals),
        'symbol': symbol,
        'detail': '转账',
        if (token != null) 'tokenAddress': token!.address,
      });
      if (mounted) Navigator.pop(context, hash);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          uncertain = attempted;
          error = attempted
              ? '未获得广播结果。请先在区块浏览器核对交易，避免重复发送。'
              : '无法读取钥匙串，请检查系统权限。';
        });
      }
    }
  }

  Widget currencyOption(TokenDefinition? currency) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (currency == null)
        ChainLogo(chain: widget.chain, size: 22)
      else
        TokenLogo(token: currency, size: 22),
      const SizedBox(width: 8),
      Text('${currency?.symbol ?? widget.chain.symbol} (${widget.chain.name})'),
    ],
  );

  @override
  Widget build(BuildContext context) => ShadDialog(
    radius: BorderRadius.circular(10),
    gap: 24,
    closeIcon: SizedBox.shrink(),
    constraints: BoxConstraints(maxWidth: 520),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    title: Text('转账 · $symbol'),
    actions: [
      ShadButton.ghost(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(uncertain ? '关闭并核对记录' : '取消'),
      ),
      if (quote != null && !uncertain)
        ShadButton.ghost(
          onPressed: busy
              ? null
              : () => setState(() {
                  quote = null;
                  error = null;
                }),
          child: Text('修改'),
        ),
      ShadButton(
        onPressed: busy || uncertain
            ? null
            : quote == null
            ? preview
            : broadcast,
        child: Text(
          busy
              ? '处理中…'
              : quote == null
              ? '预览交易'
              : '确认并发送',
        ),
      ),
    ],
    child: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '从 ${widget.account.name} 发送 $symbol · ${widget.chain.name} 主网',
              style: TextStyle(color: context.palette.mutedForeground),
            ),
            SizedBox(height: 20),
            if (quote == null) ...[
              Text('币种', style: ShadTheme.of(context).textTheme.small),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => ShadSelect<String>(
                  key: ValueKey(token?.id ?? 'native'),
                  initialValue: token?.id ?? 'native',
                  enabled: !busy && !uncertain,
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                  options: [
                    ShadOption(value: 'native', child: currencyOption(null)),
                    for (final entry in availableTokens.entries)
                      ShadOption(
                        value: entry.key,
                        child: currencyOption(entry.value),
                      ),
                  ],
                  selectedOptionBuilder: (context, value) =>
                      currencyOption(availableTokens[value]),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      token = availableTokens[value];
                      amount.clear();
                      quote = null;
                      units = null;
                      error = null;
                      balanceVersion++;
                      balanceRequest = loadBalance();
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<BigInt>(
                key: ValueKey(balanceVersion),
                future: balanceRequest,
                builder: (context, snapshot) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        snapshot.connectionState != ConnectionState.done
                            ? '当前余额：查询中…'
                            : snapshot.hasError
                            ? '当前余额：查询失败，请重试'
                            : '当前余额：${formatBalance(snapshot.data!, decimals)} $symbol',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.mutedForeground,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新当前币种余额',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh, size: 16),
                      onPressed:
                          snapshot.connectionState != ConnectionState.done
                          ? null
                          : () => setState(() {
                              balanceVersion++;
                              balanceRequest = loadBalance();
                            }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('收款地址', style: ShadTheme.of(context).textTheme.small),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: to,
                      enabled: !busy,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '从地址本选择',
                    child: ShadButton.outline(
                      key: const ValueKey('select-recipient'),
                      onPressed: busy ? null : selectRecipient,
                      child: const Icon(Icons.contacts_outlined, size: 18),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '金额 ($symbol)',
                      style: ShadTheme.of(context).textTheme.small,
                    ),
                  ),
                  FutureBuilder<BigInt>(
                    key: ValueKey('all-$balanceVersion'),
                    future: balanceRequest,
                    builder: (context, snapshot) => ShadButton.ghost(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onPressed:
                          busy ||
                              uncertain ||
                              snapshot.connectionState !=
                                  ConnectionState.done ||
                              !snapshot.hasData
                          ? null
                          : () {
                              amount.text = formatEther(
                                snapshot.data!,
                                decimals,
                              );
                              amount.selection = TextSelection.collapsed(
                                offset: amount.text.length,
                              );
                            },
                      child: const Text('ALL'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ShadInput(
                controller: amount,
                enabled: !busy && !uncertain,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final pattern = decimals == 0
                        ? RegExp(r'^\d*$')
                        : RegExp('^\\d*(\\.\\d{0,$decimals})?\$');
                    return pattern.hasMatch(newValue.text)
                        ? newValue
                        : oldValue;
                  }),
                ],
              ),
              SizedBox(height: 16),
              Text(
                '下一步将查询手续费并展示最终确认信息。',
                style: TextStyle(
                  color: context.palette.mutedForeground,
                  fontSize: 12,
                ),
              ),
            ] else ...[
              Text('确认交易', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              SelectableText(
                '网络：${widget.chain.name} 主网\n\n发送地址：${widget.account.address}\n\n收款地址：$destination\n\n转出金额：${formatEther(units!, decimals)} $symbol${token == null ? '' : '\n\n代币合约 / Mint：${token!.address}'}\n\n${widget.chain.family == Family.tron && token == null ? '资源费用预留' : '预计费用上限'}：${formatEther(quote!.fee, widget.chain.decimals)} ${widget.chain.symbol}${quote is TokenTransferQuote && (quote! as TokenTransferQuote).feeNote.isNotEmpty ? '\n\n${(quote! as TokenTransferQuote).feeNote}' : ''}',
                style: TextStyle(height: 1.6, fontSize: 12),
              ),
              SizedBox(height: 16),
              Text(
                '请核对完整地址。确认后将使用本机私钥签名并广播交易，报价 45 秒内有效。',
                style: TextStyle(
                  color: context.palette.mutedForeground,
                  fontSize: 12,
                ),
              ),
            ],
            if (error != null)
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: SelectableText(
                  error!,
                  style: TextStyle(
                    color: context.palette.destructive,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

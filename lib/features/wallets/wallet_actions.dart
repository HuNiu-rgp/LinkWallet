import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/wallet.dart';
import '../../core/token.dart';
import '../market/market_chart_page.dart';
import '../governance/tron_governance_page.dart';
import '../../core/backup_codec.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../transfers/send_dialog.dart';
import 'wallet_controller.dart';
import 'wallet_editor.dart';

class WalletActions {
  final BuildContext Function() contextOf;
  final WalletController c;
  final bool Function() isMounted;
  WalletActions(this.contextOf, this.c, this.isMounted);
  BuildContext get context => contextOf();
  bool get mounted => isMounted();
  WalletStore get store => c.store;
  void notify(String message) {
    if (!mounted) return;
    showShadDialog<void>(
      context: context,
      builder: (ctx) => ShadDialog(
        radius: BorderRadius.circular(10),
        gap: 24,
        closeIcon: SizedBox.shrink(),
        constraints: BoxConstraints(maxWidth: 520),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text('LinkWallet'),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(ctx),
            child: Text('知道了'),
          ),
        ],
        child: SelectableText(message),
      ),
    );
  }

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> renameWallet(Account account) async {
    final name = TextEditingController(text: account.name);
    var busy = false;
    String? error;
    await showShadDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => ShadDialog(
          title: const Text('修改钱包'),
          closeIcon: const SizedBox.shrink(),
          constraints: const BoxConstraints(maxWidth: 520),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          actions: [
            ShadButton.ghost(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setState(() => error = '请输入钱包名称');
                        return;
                      }
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await c.renameAccount(account, name.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (_) {
                        if (ctx.mounted) {
                          setState(() {
                            busy = false;
                            error = '保存失败，请重试';
                          });
                        }
                      }
                    },
              child: Text(busy ? '保存中…' : '保存'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinkInput(controller: name, label: '钱包名称'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(color: context.palette.destructive),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // Wait for the dialog's closing animation before disposing its input.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
  }

  Future<void> openTronGovernance({required bool vote}) async {
    final account = c.selected;
    if (c.chain.family != Family.tron || account == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TronGovernancePage(
          account: account,
          accounts: List.of(c.accounts),
          store: store,
          vote: vote,
          onAccountChanged: c.selectAccount,
        ),
      ),
    );
    if (mounted) {
      c.refreshResources();
      c.refresh();
    }
  }

  final Set<String> _openingCharts = {};
  Future<void> openChart({TokenDefinition? token}) async {
    final chain = c.chain;
    final key = token?.id ?? 'native:${chain.id}';
    if (!_openingCharts.add(key)) return;
    try {
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MarketChartPage(chain: chain, token: token),
        ),
      );
    } on FormatException catch (e) {
      notify(e.message);
    } catch (_) {
      notify('无法加载币种行情，请检查网络后重试');
    } finally {
      _openingCharts.remove(key);
    }
  }

  Future<void> browse({String? hash}) async {
    final a = c.selected;
    if (a == null) return;
    final url = c.chain.family == Family.tron
        ? '${c.chain.explorer}/#/${hash == null ? 'address/${a.address}' : 'transaction/$hash'}'
        : '${c.chain.explorer}/${hash == null ? 'address/${a.address}' : 'tx/$hash'}';
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      notify('无法打开浏览器');
    }
  }

  Future<void> viewTransaction(Map<String, dynamic> transaction) async {
    final service = ChainService(c.chain);
    Future<Map<String, String>> query() async {
      final details = await service.transactionDetails(
        transaction['hash'] as String,
      );
      if (transaction['amount'] != null) {
        details['金额'] = '${transaction['amount']} ${transaction['symbol']}';
      }
      if (transaction['from'] != null) {
        details['发送地址'] = '${transaction['from']}';
      }
      if (transaction['to'] != null) details['接收地址'] = '${transaction['to']}';
      if (transaction['tokenAddress'] != null) {
        details['代币合约'] = '${transaction['tokenAddress']}';
      }
      if (transaction['assetId'] != null) {
        details['资产标识'] = '${transaction['assetId']}';
      }
      return details;
    }

    var request = query();
    try {
      await showShadDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => ShadDialog(
            title: const Text('交易详情'),
            constraints: const BoxConstraints(maxWidth: 640),
            actions: [
              ShadButton.outline(
                onPressed: () => update(() => request = query()),
                child: const Text('重新查询'),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
            child: SizedBox(
              width: 520,
              child: FutureBuilder<Map<String, String>>(
                future: request,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Text('交易查询失败，请检查网络后重新查询。');
                  }
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: snapshot.data!.entries
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ctx.palette.mutedForeground,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(entry.value),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    } finally {
      service.dispose();
    }
  }

  Future<void> addWallet({bool create = false}) async {
    final result = await showShadDialog<Account>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WalletEditor(
        store: store,
        accounts: c.accounts,
        family: c.chain.family,
        initialChain: c.chain,
        create: create,
      ),
    );
    if (result == null || !mounted) return;
    c.update(() {
      c.accounts = [...c.accounts, result];
      c.selected = result;
      c.chain = result.preferredChain;
    });
    c.refresh();
  }

  Future<void> exportAddresses() async {
    try {
      final path = await getSaveLocation(
        suggestedName: 'linkwallet-addresses.json',
      );
      if (path == null) return;
      final content = jsonEncode({
        'version': 1,
        'wallets': c.accounts
            .map(
              (a) => {
                'name': a.name,
                'address': a.address,
                'family': a.family.name,
                if (a.chainId != null) 'chainId': a.chainId,
              },
            )
            .toList(),
      });
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(content)),
        mimeType: 'application/json',
      ).saveTo(path.path);
      notify('地址已导出。此文件不包含私钥，不能用于恢复签名钱包。');
    } catch (_) {
      notify('导出失败，请检查文件权限');
    }
  }

  Future<void> importAddresses() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      final j = jsonDecode(await file.readAsString()) as Map;
      if (j['version'] != 1) throw FormatException();
      final additions = <Account>[];
      for (final item in j['wallets'] as List) {
        final family = Family.values.byName(item['family'] as String);
        final address = validateAddress(item['address'] as String, family);
        if (![...c.accounts, ...additions].any(
          (a) =>
              a.family == family &&
              a.address == address &&
              (a.chainId == null ||
                  item['chainId'] == null ||
                  a.chainId == item['chainId']),
        )) {
          additions.add(
            Account(
              item['name'] as String,
              address,
              false,
              family,
              chainId: item['chainId'] as int?,
            ),
          );
        }
      }
      await store.save([...c.accounts, ...additions]);
      if (!mounted) return;
      c.update(() => c.accounts = [...c.accounts, ...additions]);
      if (c.selected == null && additions.isNotEmpty) {
        c.selectChain(additions.first.preferredChain);
      }
      notify('已导入 ${additions.length} 个观察钱包');
    } catch (_) {
      notify('导入失败，请选择 LinkWallet 导出的地址 JSON');
    }
  }

  Future<void> receive() async {
    final a = c.selected;
    if (a == null) return;
    await showShadDialog<void>(
      context: context,
      builder: (ctx) => ShadDialog(
        radius: BorderRadius.circular(10),
        gap: 24,
        closeIcon: SizedBox.shrink(),
        constraints: BoxConstraints(maxWidth: 520),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text('收款 · ${c.chain.name}'),
        actions: [
          ShadButton.outline(
            onPressed: () => copy(a.address),
            child: Text('复制地址'),
          ),
          ShadButton(onPressed: () => Navigator.pop(ctx), child: Text('完成')),
        ],
        child: SizedBox(
          width: 390,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: a.address,
                  size: 220,
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: 16),
              SelectableText(a.address, textAlign: TextAlign.center),
              SizedBox(height: 16),
              Text(
                '请确认发送方使用 ${c.chain.name} 网络。',
                style: TextStyle(color: context.palette.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> viewPrivateKey(Account account) async {
    if (!account.signing || !mounted) return;
    String? secret;
    String? error;
    bool busy = false;
    bool copied = false;
    try {
      await showShadDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => ShadDialog(
            radius: BorderRadius.circular(10),
            gap: 24,
            closeIcon: const SizedBox.shrink(),
            constraints: const BoxConstraints(maxWidth: 520),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(
              account.family == Family.solana ? '查看私钥（Seed）' : '查看私钥',
            ),
            actions: [
              if (secret != null)
                ShadButton.outline(
                  onPressed: () async {
                    try {
                      await copy(secret!);
                      if (ctx.mounted) update(() => copied = true);
                    } catch (_) {
                      if (ctx.mounted) update(() => error = '复制失败，请重试');
                    }
                  },
                  child: Text(copied ? '已复制' : '复制私钥'),
                )
              else
                ShadButton.outline(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final value = await store.secret(account);
                            if (ctx.mounted) {
                              update(() {
                                secret = value;
                                busy = false;
                              });
                            }
                          } catch (_) {
                            if (ctx.mounted) {
                              update(() {
                                busy = false;
                                error = '无法读取私钥，请检查系统钥匙串权限后重试';
                              });
                            }
                          }
                        },
                  child: Text(busy ? '正在读取…' : '显示私钥'),
                ),
              ShadButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name),
                  const SizedBox(height: 8),
                  SelectableText(
                    account.address,
                    style: TextStyle(
                      fontSize: 12,
                      color: ctx.palette.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('私钥可完全控制钱包资产。请在安全环境下查看，勿截图或分享给他人。'),
                  const SizedBox(height: 20),
                  if (secret != null)
                    SelectableText(
                      secret!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    )
                  else
                    const Text('••••••••••••••••••••••••••••••••'),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(color: ctx.palette.destructive),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      secret = null;
    }
  }

  Future<void> backup() async {
    final a = c.selected;
    if (a == null || !a.signing) return;
    final password = TextEditingController();
    String? error;
    bool busy = false;
    await showShadDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => ShadDialog(
          radius: BorderRadius.circular(10),
          gap: 24,
          closeIcon: SizedBox.shrink(),
          constraints: BoxConstraints(maxWidth: 520),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          title: Text('加密备份钱包'),
          actions: [
            ShadButton.ghost(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text('取消'),
            ),
            ShadButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (password.text.length < 12) {
                        update(() => error = '密码至少 12 位');
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final secret = await store.secret(a);
                        if (!ctx.mounted) return;
                        final encrypted = await compute(encryptBackup, [
                          secret,
                          password.text,
                        ]);
                        final path = await getSaveLocation(
                          suggestedName:
                              'linkwallet-${a.family.name}-backup.json',
                        );
                        if (path == null) {
                          if (ctx.mounted) update(() => busy = false);
                          return;
                        }
                        final content = jsonEncode({
                          'version': 1,
                          'family': a.family.name,
                          if (a.chainId != null) 'chainId': a.chainId,
                          'name': a.name,
                          'address': a.address,
                          'keystore': jsonDecode(encrypted),
                        });
                        await XFile.fromData(
                          Uint8List.fromList(utf8.encode(content)),
                          mimeType: 'application/json',
                        ).saveTo(path.path);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (_) {
                        if (ctx.mounted) {
                          update(() {
                            busy = false;
                            error = '备份失败，请检查钥匙串和文件权限';
                          });
                        }
                      }
                    },
              child: Text(busy ? '正在加密…' : '保存加密备份'),
            ),
          ],
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('用独立密码加密私钥。请妥善保存备份与密码，这是恢复钱包所必需的。'),
                SizedBox(height: 20),
                LinkInput(
                  controller: password,
                  obscureText: true,
                  label: '备份密码（至少 12 位）',
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: context.palette.destructive),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Controllers belong to a route and are released after its exit animation.
    await Future<void>.delayed(Duration(milliseconds: 300));
    password.dispose();
  }

  Future<void> send({TokenDefinition? token}) async {
    final a = c.selected;
    if (a == null || !a.signing) return;
    final network = c.chain;
    final hash = await showShadDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SendDialog(
        account: a,
        chain: network,
        store: store,
        onBroadcast: (transaction) =>
            c.recordBroadcast(network, a, transaction),
        token: token,
        tokens: c.tokens.balances.map((entry) => entry.token).toList(),
      ),
    );
    if (hash != null) {
      notify('交易已广播，等待链上确认。\n\n$hash');
      c.refresh();
    }
  }
}

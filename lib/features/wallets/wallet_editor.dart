import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/wallet.dart';
import '../../core/backup_codec.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';

class WalletEditor extends StatefulWidget {
  final WalletStore store;
  final List<Account> accounts;
  final Family family;
  final bool create;
  final Chain? initialChain;
  const WalletEditor({
    super.key,
    required this.store,
    required this.accounts,
    required this.family,
    required this.create,
    this.initialChain,
  });
  @override
  State<WalletEditor> createState() => _WalletEditorState();
}

class _WalletEditorState extends State<WalletEditor> {
  final name = TextEditingController(),
      value = TextEditingController(),
      password = TextEditingController();
  late Chain chain =
      widget.initialChain ??
      Chain.all.firstWhere((c) => c.family == widget.family);
  String mode = 'address';
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    value.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var input = value.text;
      var f = chain.family;
      var label = name.text;
      if (widget.create) input = widget.store.generateKey();
      if (mode == 'backup' && !widget.create) {
        final file = await openFile(
          acceptedTypeGroups: [
            XTypeGroup(label: '备份', extensions: ['json']),
          ],
        );
        if (file == null) {
          if (mounted) setState(() => busy = false);
          return;
        }
        final j = jsonDecode(await file.readAsString()) as Map;
        if (j['version'] != 1) throw FormatException();
        f = Family.values.byName(j['family'] as String);
        if (f != chain.family) throw const FormatException();
        input = await compute(decryptBackup, [
          jsonEncode(j['keystore']),
          password.text,
        ]);
        if (addressForKey(input, f) != j['address']) {
          throw FormatException();
        }
        if (label.isEmpty) label = j['name'] as String;
      }
      final a = await widget.store.add(
        label,
        input,
        widget.create || mode != 'address',
        f,
        widget.accounts,
        chainId: chain.id,
      );
      if (mounted) Navigator.pop(context, a);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '无法导入：请检查格式、备份密码或地址是否已存在。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ShadDialog(
    radius: BorderRadius.circular(10),
    gap: 24,
    closeIcon: SizedBox.shrink(),
    constraints: BoxConstraints(maxWidth: 520),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    title: Text(widget.create ? '创建钱包' : '导入钱包'),
    actions: [
      ShadButton.ghost(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text('取消'),
      ),
      ShadButton(
        onPressed: busy ? null : submit,
        child: Text(
          busy
              ? '处理中…'
              : widget.create
              ? '创建钱包'
              : mode == 'backup'
              ? '选择备份并恢复'
              : '导入',
        ),
      ),
    ],
    child: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.create
                  ? '为当前网络创建独立密钥，保存在本机钥匙串。创建后请到设置中导出加密备份。'
                  : '导入公开地址可查看资产；导入私钥可签名转账。',
              style: TextStyle(
                color: context.palette.mutedForeground,
                height: 1.6,
              ),
            ),
            SizedBox(height: 20),
            LinkSelect<Chain>(
              label: '网络类型',
              value: chain,
              enabled: !busy,
              options: {for (final c in Chain.all) c: c.name},
              onChanged: (c) => setState(() => chain = c),
            ),
            SizedBox(height: 16),
            LinkInput(
              controller: name,
              enabled: !busy,
              label: '钱包名称',
              placeholder: '例如：日常钱包',
            ),
            SizedBox(height: 16),
            if (!widget.create) ...[
              LinkSelect<String>(
                label: '导入方式',
                value: mode,
                enabled: !busy,
                options: {
                  'address': '公开地址 · 仅观察',
                  'private': '私钥 / Solana seed · 十六进制',
                  'backup': 'LinkWallet 加密备份',
                },
                onChanged: (m) => setState(() => mode = m),
              ),
              SizedBox(height: 16),
              if (mode == 'backup')
                LinkInput(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  label: '备份密码',
                )
              else
                LinkInput(
                  controller: value,
                  enabled: !busy,
                  obscureText: mode == 'private',
                  autocorrect: false,
                  enableSuggestions: false,
                  label: mode == 'address' ? '钱包地址' : '64 位十六进制私钥 / seed',
                ),
            ],
            if (error != null)
              Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
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

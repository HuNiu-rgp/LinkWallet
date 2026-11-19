import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/models.dart';
import '../../core/token.dart';
import '../../core/token_service.dart';
import '../../core/chain_service.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/logos.dart';

class AddTokenDialog extends StatefulWidget {
  final Chain chain;
  final String owner;
  final Set<String> existingIds;
  const AddTokenDialog({
    super.key,
    required this.chain,
    required this.owner,
    required this.existingIds,
  });
  @override
  State<AddTokenDialog> createState() => _AddTokenDialogState();
}

class _AddTokenDialogState extends State<AddTokenDialog> {
  final address = TextEditingController(), label = TextEditingController();
  TokenDefinition? candidate;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    address.dispose();
    label.dispose();
    super.dispose();
  }

  Future<void> inspect() async {
    setState(() {
      busy = true;
      error = null;
    });
    final service = ChainService(widget.chain);
    try {
      final result = await TokenService(
        service,
      ).inspect(address.text, widget.owner, label: label.text);
      if (widget.existingIds.contains(result.id)) throw StateError('此代币已在列表中');
      if (mounted) {
        setState(() {
          candidate = result;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException
              ? e.message
              : e is StateError
              ? e.message.toString()
              : '读取失败，请核对合约地址和网络后重试';
        });
      }
    } finally {
      service.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ShadDialog(
    title: const Text('添加自定义代币'),
    constraints: const BoxConstraints(maxWidth: 520),
    radius: BorderRadius.circular(10),
    gap: 20,
    closeIcon: const SizedBox.shrink(),
    actions: [
      ShadButton.ghost(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (candidate != null)
        ShadButton.outline(
          onPressed: () => setState(() => candidate = null),
          child: const Text('修改'),
        ),
      ShadButton(
        onPressed: busy
            ? null
            : candidate == null
            ? inspect
            : () => Navigator.pop(context, candidate),
        child: Text(
          busy
              ? '读取中…'
              : candidate == null
              ? '读取代币信息'
              : '添加到资产列表',
        ),
      ),
    ],
    child: SizedBox(
      width: 450,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChainLogo(chain: widget.chain),
              const SizedBox(width: 10),
              Text('${widget.chain.name} 主网'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '按合约地址识别代币；显示名称仅作标签。添加后可查询余额并预览转账。Token-2022 扩展代币暂仅支持查询。',
            style: TextStyle(color: context.palette.mutedForeground),
          ),
          const SizedBox(height: 20),
          if (candidate == null) ...[
            LinkInput(
              controller: address,
              label: widget.chain.family == Family.solana
                  ? 'Mint 地址'
                  : '代币合约地址',
              enabled: !busy,
            ),
            const SizedBox(height: 16),
            LinkInput(
              controller: label,
              label: widget.chain.family == Family.solana
                  ? '显示名称（必填）'
                  : '显示名称（可选，默认读取链上符号）',
              enabled: !busy,
            ),
          ] else ...[
            Text(
              '${candidate!.symbol} · 精度 ${candidate!.decimals}',
              style: ShadTheme.of(context).textTheme.large,
            ),
            const SizedBox(height: 12),
            SelectableText(candidate!.address),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: TextStyle(color: context.palette.destructive),
              ),
            ),
        ],
      ),
    ),
  );
}

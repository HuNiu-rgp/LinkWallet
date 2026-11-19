import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/address_book.dart';
import '../../core/wallet.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/logos.dart';
import '../../shared/widgets/wallet_card.dart';

class AddressBookPage extends StatefulWidget {
  const AddressBookPage({super.key});
  @override
  State<AddressBookPage> createState() => _AddressBookPageState();
}

class _AddressBookPageState extends State<AddressBookPage> {
  final repository = AddressBookRepository();
  List<AddressEntry> entries = [];
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repository.load();
      if (mounted) {
        setState(() {
          entries = result;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '地址本读取失败，请重试';
          loading = false;
        });
      }
    }
  }

  Future<void> edit([AddressEntry? entry]) async {
    final result = await showShadDialog<AddressEntry>(
      context: context,
      builder: (_) => AddressEntryEditor(entry: entry, existing: entries),
    );
    if (result == null || !mounted) return;
    final updated = [...entries];
    if (entry == null) {
      updated.add(result);
    } else {
      updated[updated.indexOf(entry)] = result;
    }
    await save(updated);
  }

  Future<void> save(List<AddressEntry> updated) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await repository.save(updated);
      if (mounted) setState(() => entries = updated);
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> remove(AddressEntry entry) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('删除地址'),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
        child: Text('确定删除「${entry.name}」吗？'),
      ),
    );
    if (confirmed == true && mounted) {
      await save(entries.where((e) => e != entry).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '地址本',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  '保存常用收款地址，按名称和链管理。数据保存在本机。',
                  style: TextStyle(color: context.palette.mutedForeground),
                ),
              ],
            ),
          ),
          ShadButton(
            onPressed: loading || saving || error != null ? null : () => edit(),
            child: const Text('＋ 添加地址'),
          ),
        ],
      ),
      const SizedBox(height: 28),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  error!,
                  style: TextStyle(color: context.palette.destructive),
                ),
              ),
              ShadButton.ghost(
                onPressed: saving ? null : load,
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      walletCard(
        context,
        loading
            ? const Center(child: CircularProgressIndicator())
            : entries.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('暂无保存的地址，点击“添加地址”创建。')),
              )
            : Column(
                children: entries
                    .map(
                      (entry) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: ChainLogo(chain: entry.chain, size: 32),
                        title: Text(entry.name),
                        subtitle: SelectableText(
                          entry.address,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.mutedForeground,
                          ),
                        ),
                        isThreeLine: false,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ShadButton.outline(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: entry.address),
                              ),
                              child: const Text('复制'),
                            ),
                            const SizedBox(width: 8),
                            ShadButton.outline(
                              onPressed: saving ? null : () => edit(entry),
                              child: const Text('修改'),
                            ),
                            const SizedBox(width: 8),
                            ShadButton.ghost(
                              onPressed: saving ? null : () => remove(entry),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
}

class AddressEntryEditor extends StatefulWidget {
  final AddressEntry? entry;
  final List<AddressEntry> existing;
  const AddressEntryEditor({super.key, this.entry, required this.existing});
  @override
  State<AddressEntryEditor> createState() => _AddressEntryEditorState();
}

class _AddressEntryEditorState extends State<AddressEntryEditor> {
  late final name = TextEditingController(text: widget.entry?.name);
  late final address = TextEditingController(text: widget.entry?.address);
  late Chain chain = widget.entry?.chain ?? Chain.all.first;
  String? error;
  @override
  void dispose() {
    name.dispose();
    address.dispose();
    super.dispose();
  }

  void submit() {
    try {
      if (name.text.trim().isEmpty) throw const FormatException('请输入名称');
      final normalized = validateAddress(address.text, chain.family);
      if (widget.existing.any(
        (e) =>
            e != widget.entry &&
            e.chainId == chain.id &&
            (chain.family == Family.evm
                ? e.address.toLowerCase() == normalized.toLowerCase()
                : e.address == normalized),
      )) {
        throw const FormatException('该链的地址已存在');
      }
      Navigator.pop(
        context,
        AddressEntry(name.text.trim(), normalized, chain.id),
      );
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = '地址格式不正确，请检查地址与所选链');
    }
  }

  @override
  Widget build(BuildContext context) => ShadDialog(
    title: Text(widget.entry == null ? '添加地址' : '修改地址'),
    constraints: const BoxConstraints(maxWidth: 520),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    actions: [
      ShadButton.ghost(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ShadButton(onPressed: submit, child: const Text('保存')),
    ],
    child: SizedBox(
      width: 450,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinkInput(controller: name, label: '名称', placeholder: '例如：常用收款地址'),
            const SizedBox(height: 16),
            LinkSelect<Chain>(
              label: '链',
              value: chain,
              options: {for (final c in Chain.all) c: c.name},
              onChanged: (c) => setState(() => chain = c),
            ),
            const SizedBox(height: 16),
            LinkInput(controller: address, label: '地址'),
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
    ),
  );
}

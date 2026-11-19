import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/models.dart';
import '../theme_context.dart';

class WalletAccountSelector extends StatelessWidget {
  final Account value;
  final List<Account> accounts;
  final ValueChanged<Account> onChanged;
  const WalletAccountSelector({
    super.key,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: LayoutBuilder(
        builder: (context, constraints) => ShadSelect<String>(
          key: const ValueKey('governance-wallet-selector'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          initialValue: value.address,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          options: accounts.map(
            (account) => ShadOption<String>(
              value: account.address,
              child: _label(context, account),
            ),
          ),
          selectedOptionBuilder: (context, address) => _label(
            context,
            accounts.firstWhere(
              (a) => a.address == address,
              orElse: () => value,
            ),
          ),
          onChanged: (address) {
            if (address != null && address != value.address) {
              onChanged(accounts.firstWhere((a) => a.address == address));
            }
          },
        ),
      ),
    ),
  );
  Widget _label(BuildContext context, Account account) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${account.name}${account.signing ? '' : ' · 仅观察'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      const SizedBox(height: 2),
      Text(
        account.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: context.palette.mutedForeground,
        ),
      ),
    ],
  );
}

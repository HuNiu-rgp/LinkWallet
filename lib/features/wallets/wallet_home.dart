import 'package:flutter/material.dart';
import '../../core/wallet.dart';
import '../../app/theme_controller.dart';
import '../../app/wallet_shell.dart';
import '../dashboard/dashboard_page.dart';
import '../settings/settings_page.dart';
import '../address_book/address_book_page.dart';
import 'wallet_controller.dart';
import 'wallet_actions.dart';

class WalletHome extends StatefulWidget {
  final WalletStore? store;
  final ThemeController theme;
  const WalletHome({super.key, this.store, required this.theme});
  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  late final WalletController controller = WalletController(
    widget.store ?? WalletStore(),
  );
  late final WalletActions actions = WalletActions(
    () => context,
    controller,
    () => mounted,
  );
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.tokens]),
    builder: (context, _) => WalletShell(
      c: controller,
      theme: widget.theme,
      child: controller.page == 4
          ? const AddressBookPage()
          : controller.page == 3
          ? SettingsPage(c: controller, actions: actions, theme: widget.theme)
          : DashboardPage(c: controller, actions: actions),
    ),
  );
}

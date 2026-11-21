import 'package:flutter/material.dart';
import '../../core/wallet.dart';
import '../../app/theme_controller.dart';
import '../../app/wallet_shell.dart';
import '../dashboard/dashboard_page.dart';
import '../governance/tron_governance_page.dart';
import '../settings/settings_page.dart';
import '../address_book/address_book_page.dart';
import 'wallet_controller.dart';
import 'wallet_actions.dart';
import '../../platform/wallet_menu_bar.dart';
import 'asset_refresh_scheduler.dart';
import '../monitoring/wallet_transfer_monitor.dart';

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
  late final WalletMenuBar menuBar = WalletMenuBar(controller);
  late final AssetRefreshScheduler assetRefresh = AssetRefreshScheduler(
    controller,
  );

  late final transferMonitor = WalletTransferMonitor(controller);

  @override
  void initState() {
    super.initState();
    menuBar.start();
    controller.load().then((_) {
      if (mounted) transferMonitor.start();
    });
    assetRefresh.start();
  }

  @override
  void dispose() {
    transferMonitor.dispose();
    assetRefresh.dispose();
    menuBar.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.tokens]),
    builder: (context, _) => WalletShell(
      c: controller,
      actions: actions,
      theme: widget.theme,
      scrollable: controller.governanceVote == null,
      child: controller.governanceVote != null && controller.selected != null
          ? TronGovernancePage(
              embedded: true,
              account: controller.selected!,
              accounts: controller.accounts,
              store: controller.store,
              vote: controller.governanceVote!,
              onClose: controller.closeGovernance,
              onVoteChanged: (vote) => controller.openGovernance(vote: vote),
            )
          : controller.page == 4
          ? const AddressBookPage()
          : controller.page == 3
          ? SettingsPage(
              c: controller,
              actions: actions,
              theme: widget.theme,
              monitor: transferMonitor,
            )
          : DashboardPage(c: controller, actions: actions),
    ),
  );
}

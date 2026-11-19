import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../core/wallet.dart';
import '../features/wallets/wallet_home.dart';
import 'theme_controller.dart';

class LinkWalletApp extends StatefulWidget {
  final WalletStore? store;
  final ThemeController? theme;
  const LinkWalletApp({super.key, this.store, this.theme});
  @override
  State<LinkWalletApp> createState() => _LinkWalletAppState();
}

class _LinkWalletAppState extends State<LinkWalletApp> {
  late final ThemeController theme = widget.theme ?? ThemeController();
  @override
  void initState() {
    super.initState();
    theme.load();
  }

  @override
  void dispose() {
    if (widget.theme == null) theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: theme,
    builder: (context, _) => ShadApp(
      title: 'LinkWallet',
      themeMode: theme.mode,
      theme: theme.data(Brightness.light),
      darkTheme: theme.data(Brightness.dark),
      home: WalletHome(store: widget.store, theme: theme),
    ),
  );
}

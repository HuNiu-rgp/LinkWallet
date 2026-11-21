import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../features/wallets/wallet_controller.dart';
import '../core/models.dart';
import '../shared/formatters.dart';

/// The native menu receives public display data only, never wallet secrets.
class WalletMenuBar {
  static const channelName = 'linkwallet/menu_bar';
  final WalletController controller;
  final MethodChannel channel;
  bool _disposed = false, _scheduled = false, _started = false;
  WalletMenuBar(this.controller, {MethodChannel? channel})
    : channel = channel ?? const MethodChannel(channelName);

  String _id(Account account) =>
      '${account.family.name}:${account.chainId}:${account.address}';

  Map<String, dynamic> snapshot() {
    final c = controller;
    return {
      'network': '${c.chain.name} 主网',
      'loading': c.booting,
      'error': c.startupError != null,
      'selectedId': c.selected == null ? null : _id(c.selected!),
      'name': c.selected?.name,
      'address': c.selected?.address,
      'refreshing': c.assetsLoading || c.tokens.loading,
      'assets': c.selected == null
          ? <Map<String, String>>[]
          : [
              {
                'symbol': c.chain.symbol,
                'balance': c.hidden
                    ? '••••'
                    : c.balanceError != null
                    ? '查询失败'
                    : c.balance == null
                    ? '—'
                    : formatBalance(c.balance!, c.chain.decimals),
              },
              for (final entry in c.tokens.balances)
                {
                  'symbol': entry.token.symbol,
                  'balance': c.hidden
                      ? '••••'
                      : entry.error != null
                      ? '查询失败'
                      : entry.amount == null
                      ? '—'
                      : formatBalance(entry.amount!, entry.token.decimals),
                },
            ],
      'wallets': [
        for (final account in c.accounts.where((a) => a.supportsChain(c.chain)))
          {
            'id': _id(account),
            'name': account.name,
            'address': account.address,
          },
      ],
    };
  }

  void start({bool? enabled}) {
    if (_disposed ||
        _started ||
        !(enabled ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS))) {
      return;
    }
    _started = true;
    channel.setMethodCallHandler(_handle);
    controller.addListener(_schedule);
    controller.tokens.addListener(_schedule);
    _schedule();
  }

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'selectWallet':
        final matches = controller.accounts.where(
          (a) => a.supportsChain(controller.chain) && _id(a) == call.arguments,
        );
        if (matches.isNotEmpty) controller.selectAccount(matches.first);
      case 'refreshAssets':
        if (!controller.assetsLoading && !controller.tokens.loading) {
          await controller.refreshAssets();
        }
      case 'refreshSnapshot':
        _schedule();
    }
  }

  void _schedule() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() async {
      _scheduled = false;
      if (_disposed) return;
      try {
        await channel.invokeMethod<void>('update', snapshot());
      } on MissingPluginException {
        // Other platforms and widget tests do not provide a native status item.
      } on PlatformException {
        // A menu refresh must not interrupt the wallet's primary UI.
      }
    });
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_schedule);
    controller.tokens.removeListener(_schedule);
    if (_started) channel.setMethodCallHandler(null);
  }
}

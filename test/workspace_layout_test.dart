import 'package:chainvault/app/theme_controller.dart';
import 'package:chainvault/app/wallet_shell.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/dashboard/dashboard_page.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LayoutController extends WalletController {
  LayoutController() : super(WalletStore());
  // Layout interactions must not contact live networks.
  @override
  Future<void> refresh() async {}
}

void main() {
  for (final width in [1200.0, 1000.0, 760.0]) {
    testWidgets(
      'Workspace stays usable at $width pixels and switches wallets',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const primary = Account(
          '日常钱包',
          'TPAGWJZZwCKbQkJcJcrTfEZCQj6AVi5ugV',
          true,
          Family.tron,
        );
        const observer = Account(
          '观察钱包',
          'TW6bSamplePublicAddress9m2F',
          false,
          Family.tron,
        );
        const otherChain = Account(
          'ETH 钱包',
          '0x1111111111111111111111111111111111111111',
          false,
          Family.evm,
        );
        final c = LayoutController()
          ..booting = false
          ..accounts = [primary, observer, otherChain]
          ..selected = primary
          ..balance = BigInt.from(128500000)
          ..resources = TronResources(
            BigInt.from(65000),
            BigInt.from(420),
            energyLimit: BigInt.from(100000),
            bandwidthLimit: BigInt.from(600),
          )
          ..transactions = [
            {
              'incoming': true,
              'amount': '200.000',
              'symbol': 'USDT',
              'tokenAddress': presetTokens(Chain.all.first).first.address,
              'status': 'SUCCESS',
              'timestamp': DateTime.now().toIso8601String(),
              'counterparty': observer.address,
            },
            {
              'incoming': false,
              'amount': '0.500',
              'symbol': 'TRX',
              'detail': 'TransferContract',
              'status': 'SUCCESS',
              'timestamp': DateTime.now().toIso8601String(),
              'counterparty': observer.address,
            },
          ];
        c.tokens.balances = [
          TokenBalance(
            presetTokens(c.chain).first,
            amount: BigInt.from(1248000000),
          ),
        ];
        final theme = ThemeController();
        addTearDown(c.dispose);
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          ShadApp(
            theme: theme.data(Brightness.light),
            home: Builder(
              builder: (context) {
                final actions = WalletActions(
                  () => context,
                  c,
                  () => context.mounted,
                );
                return ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => WalletShell(
                    c: c,
                    actions: actions,
                    theme: theme,
                    child: DashboardPage(c: c, actions: actions),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ETH 钱包'), findsNothing);
        final assets = tester.getTopLeft(find.text('我的资产'));
        final history = tester.getTopLeft(find.text('最近交易'));
        if (width == 1200) {
          expect((assets.dy - history.dy).abs(), lessThan(8));
          expect(history.dx, greaterThan(assets.dx + 300));
        } else {
          expect(history.dy, greaterThan(assets.dy));
        }
        expect(find.text('+200.000 USDT'), findsOneWidget);
        expect(find.text('-0.500 TRX'), findsNothing);
        await tester.tap(find.byType(ShadSwitch));
        await tester.pumpAndSettle();
        expect(find.text('-0.500 TRX'), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('sidebar-wallet-${observer.address}')),
        );
        await tester.pumpAndSettle();
        expect(c.selected, observer);
        final send = tester.widget<ShadButton>(
          find.byKey(const ValueKey('transfer-native')),
        );
        expect(send.onPressed, isNull);
        expect(find.text('仅观察'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

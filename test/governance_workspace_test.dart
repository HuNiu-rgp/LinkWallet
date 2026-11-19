import 'package:chainvault/app/wallet_shell.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/governance/tron_governance_page.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/shared/widgets/back_to_assets_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'governance_flow_test.dart' show FixtureService, owner, sr;

void main() {
  for (final width in [1254.0, 1000.0, 760.0]) {
    testWidgets(
      'Governance workspace at $width keeps wallet navigation and permissions',
      (tester) async {
        tester.view.physicalSize = Size(width, 854);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final signing = Account('日常钱包', owner, true, Family.tron);
        final observing = Account('观察钱包', sr, false, Family.tron);
        final c = WalletController(WalletStore())
          ..accounts = [signing, observing]
          ..selected = signing;
        addTearDown(c.dispose);
        final service = FixtureService();
        await tester.pumpWidget(
          ShadApp(
            home: Builder(
              builder: (context) {
                final actions = WalletActions(
                  () => context,
                  c,
                  () => context.mounted,
                );
                return TronGovernancePage(
                  account: signing,
                  accounts: c.accounts,
                  store: c.store,
                  vote: false,
                  service: service,
                  onAccountChanged: (account) =>
                      c.update(() => c.selected = account),
                  workspaceBuilder: (child, onSelect, voting) =>
                      ListenableBuilder(
                        listenable: c,
                        builder: (_, _) => WalletShell(
                          c: c,
                          actions: actions,
                          scrollable: false,
                          title: voting ? '投票' : '质押与资源',
                          leading: const BackToAssetsButton(),
                          onWalletChanged: onSelect,
                          child: child,
                        ),
                      ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('我的钱包'), findsOneWidget);
        expect(find.text('可用 TRX'), findsOneWidget);
        expect(find.text('获取能量'), findsOneWidget);
        expect(find.text('获取带宽'), findsOneWidget);
        expect(find.text('资源明细'), findsOneWidget);
        await tester.tap(find.text('投票'));
        await tester.pumpAndSettle();
        expect(find.text('分配 50 票'), findsOneWidget);
        expect(find.text('总票权'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(ValueKey('sidebar-wallet-${observing.address}')),
        );
        await tester.pumpAndSettle();
        expect(c.selected, observing);
        final allocation = tester.widget<ShadButton>(
          find.widgetWithText(ShadButton, '分配 50 票'),
        );
        expect(allocation.onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

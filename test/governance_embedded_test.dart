import 'package:chainvault/app/wallet_shell.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/dashboard/dashboard_page.dart';
import 'package:chainvault/features/governance/tron_governance_page.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'governance_flow_test.dart' show FixtureService, owner, sr;

class EmbeddedController extends WalletController {
  EmbeddedController() : super(WalletStore());
  @override
  Future<void> showWallet() async {}
}

class RouteCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  for (final width in [1200.0, 1000.0, 760.0]) {
    testWidgets(
      'Embedded governance at $width keeps a single route and shell',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final signing = Account('日常钱包', owner, true, Family.tron);
        final observing = Account('观察钱包', sr, false, Family.tron);
        final c = EmbeddedController()
          ..booting = false
          ..selected = signing
          ..accounts = [signing, observing];
        addTearDown(c.dispose);
        final observer = RouteCounter();
        final service = FixtureService();
        await tester.pumpWidget(
          ShadApp(
            navigatorObservers: [observer],
            home: Builder(
              builder: (context) {
                final actions = WalletActions(
                  () => context,
                  c,
                  () => context.mounted,
                );
                return ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => WalletShell(
                    c: c,
                    actions: actions,
                    scrollable: c.governanceVote == null,
                    child: c.governanceVote == null
                        ? DashboardPage(c: c, actions: actions)
                        : TronGovernancePage(
                            embedded: true,
                            account: c.selected!,
                            accounts: c.accounts,
                            store: c.store,
                            service: service,
                            vote: c.governanceVote!,
                            onClose: c.closeGovernance,
                            onVoteChanged: (vote) =>
                                c.openGovernance(vote: vote),
                          ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final shell = tester.element(find.byType(WalletShell));
        final pushes = observer.pushes;
        await tester.tap(find.text('质押'));
        await tester.pumpAndSettle();
        expect(c.governanceVote, false);
        expect(observer.pushes, pushes);
        expect(find.byType(WalletShell), findsOneWidget);
        expect(
          identical(shell, tester.element(find.byType(WalletShell))),
          isTrue,
        );
        expect(find.text('自行质押：100.000 TRX'), findsOneWidget);
        await tester.tap(find.text('投票'));
        await tester.pumpAndSettle();
        expect(c.governanceVote, true);
        expect(find.text('分配 50 票'), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('sidebar-wallet-${observing.address}')),
        );
        await tester.pumpAndSettle();
        expect(c.selected, observing);
        expect(c.governanceVote, true);
        expect(
          tester
              .widget<ShadButton>(find.widgetWithText(ShadButton, '分配 50 票'))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('返回资产'));
        await tester.pumpAndSettle();
        expect(c.governanceVote, isNull);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(observer.pushes, pushes);
        await tester.tap(find.text('投票'));
        await tester.pumpAndSettle();
        expect(c.governanceVote, true);
        expect(observer.pushes, pushes);
        c.selectChain(Chain.all.last);
        await tester.pumpAndSettle();
        expect(c.governanceVote, isNull);
        expect(find.byType(TronGovernancePage), findsNothing);
        expect(find.byType(WalletShell), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

import 'package:chainvault/core/models.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/wallet_store.dart';
import 'package:chainvault/features/dashboard/asset_card.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/transfers/send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RecordingActions extends WalletActions {
  TokenDefinition? sentToken;
  int calls = 0;
  RecordingActions(super.contextOf, super.c, super.isMounted);
  @override
  Future<void> send({TokenDefinition? token}) async {
    calls++;
    sentToken = token;
  }
}

void main() {
  testWidgets(
    'Asset row transfer buttons bind the selected asset and disable watch-only accounts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WalletController(WalletStore());
      c.selected = const Account(
        'Wallet',
        'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
        true,
        Family.tron,
      );
      final token = presetTokens(c.chain).single;
      c.tokens.balances = [TokenBalance(token, amount: BigInt.one)];
      late RecordingActions actions;
      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) {
              actions = RecordingActions(
                () => context,
                c,
                () => context.mounted,
              );
              return Scaffold(
                body: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => AssetCard(c: c, actions: actions),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('转账'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('transfer-native')));
      expect(actions.calls, 1);
      expect(actions.sentToken, isNull);
      await tester.tap(find.byKey(ValueKey('transfer-${token.id}')));
      expect(actions.calls, 2);
      expect(actions.sentToken!.id, token.id);
      c.update(
        () => c.selected = Account(
          'Watch',
          c.selected!.address,
          false,
          Family.tron,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(find.byKey(const ValueKey('transfer-native')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ShadButton>(find.byKey(ValueKey('transfer-${token.id}')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'Token transfer dialog names the selected token and uses its amount label',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chain = Chain.all.first;
      await tester.pumpWidget(
        ShadApp(
          home: SendDialog(
            account: const Account(
              'Wallet',
              'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
              true,
              Family.tron,
            ),
            chain: chain,
            store: WalletStore(),
            token: presetTokens(chain).single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('转账 · USDT'), findsOneWidget);
      expect(find.text('金额 (USDT)'), findsOneWidget);
      expect(find.text('金额 (TRX)'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

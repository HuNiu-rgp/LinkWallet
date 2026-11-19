import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/dashboard/balance_card.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Wallet displays full selectable address and copies it to clipboard',
    (tester) async {
      const address = 'TTpsHxxb9QXGnMCEZw3ZJA71wzCze7ENBd';
      final c = WalletController(WalletStore())
        ..selected = const Account('Wallet', address, true, Family.tron);
      addTearDown(c.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => BalanceCard(
                c: c,
                actions: WalletActions(() => context, c, () => context.mounted),
              ),
            ),
          ),
        ),
      );
      expect(find.text('质押'), findsOneWidget);
      expect(find.text('投票'), findsOneWidget);
      expect(find.text('当前钱包余额'), findsNothing);
      expect(find.text(address), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        address,
      );
      expect(find.text('TTpsHxxb9Q…Cze7ENBd'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('复制地址'));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(copied, address);
      expect(find.text('地址已复制'), findsOneWidget);
      expect(find.byType(ShadDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

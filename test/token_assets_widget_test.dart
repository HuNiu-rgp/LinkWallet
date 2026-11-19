import 'package:chainvault/core/models.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/wallet_store.dart';
import 'package:chainvault/features/dashboard/asset_card.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Assets show token balances and explicit failures; custom token dialog uses shadcn',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WalletController(WalletStore());
      c.selected = const Account(
        '观察地址',
        'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
        false,
        Family.tron,
      );
      c.balance = BigInt.from(4000019);
      c.tokens.balances = [
        TokenBalance(
          presetTokens(c.chain).single,
          amount: BigInt.from(1234567),
        ),
        const TokenBalance(
          TokenDefinition(
            chainId: 728126428,
            address: 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
            symbol: 'TEST',
            decimals: 6,
            name: '自定义代币',
            custom: true,
          ),
          error: '查询失败',
        ),
      ];
      await tester.pumpWidget(
        ShadApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ListenableBuilder(
                listenable: c,
                builder: (context, _) => AssetCard(
                  c: c,
                  actions: WalletActions(
                    () => context,
                    c,
                    () => context.mounted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('4.000 TRX'), findsOneWidget);
      expect(find.text('1.235 USDT'), findsOneWidget);
      expect(find.text('Tether USD · TRC20'), findsNothing);
      expect(find.text('TRON · 原生币'), findsNothing);
      expect(find.text('TR7NHqjeKQ…gjLj6t'), findsNothing);
      expect(find.text('查询失败'), findsOneWidget);
      expect(find.text('0 TEST'), findsNothing);
      c.toggleHidden();
      await tester.pumpAndSettle();
      expect(find.text('1.235 USDT'), findsNothing);
      expect(find.text('4.000 TRX'), findsNothing);
      await tester.tap(find.text('＋ 添加代币'));
      await tester.pumpAndSettle();
      expect(find.text('添加自定义代币'), findsOneWidget);
      expect(find.byType(ShadInput), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}

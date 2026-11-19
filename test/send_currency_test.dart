import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/features/transfers/send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Switching transfer currency updates units and clears the amount',
    (tester) async {
      final chain = Chain.all.first;
      final token = presetTokens(chain).first;
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: SendDialog(
              account: const Account(
                '钱包',
                'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
                true,
                Family.tron,
              ),
              chain: chain,
              store: WalletStore(),
              tokens: [token],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('金额 (TRX)'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, '12');
      await tester.tap(find.byType(ShadSelect<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USDT (TRON)').last);
      await tester.pumpAndSettle();
      expect(find.text('金额 (USDT)'), findsOneWidget);
      expect(find.text('转账 · USDT'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

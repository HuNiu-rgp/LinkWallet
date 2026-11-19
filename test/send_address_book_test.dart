import 'package:chainvault/core/address_book.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/transfers/send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'Recipient picker filters by chain and fills the selected address',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const address = 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC';
      await AddressBookRepository().save([
        const AddressEntry('TRON收款人', address, 728126428),
        const AddressEntry(
          '其他链收款人',
          '0x0000000000000000000000000000000000000001',
          1,
        ),
      ]);
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: SendDialog(
              account: const Account('钱包', address, true, Family.tron),
              chain: Chain.all.first,
              store: WalletStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-recipient')));
      await tester.pumpAndSettle();
      expect(find.text('TRON收款人'), findsOneWidget);
      expect(find.text('其他链收款人'), findsNothing);
      await tester.tap(find.text('TRON收款人'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        address,
      );
      expect(find.text('选择收款地址 · TRON'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
